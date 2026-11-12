import com.mesting.music.QishuiAudioFailure
import com.mesting.music.QishuiAudioReason
import com.mesting.music.QishuiAudioStep
import com.mesting.music.QishuiOfficialAudioPreparation
import java.io.File
import java.util.concurrent.CancellationException

/** Exercises production preparation with real files and normalised parents.
 * Windows uses an existing-directory /./ spelling to reproduce the old exact
 * string rejection. It does not emulate Android symlinks, codecs or playback.
 */
object QishuiAudioPreparationHostTest {
    private var passed = 0
    private var number = 0
    private fun test(name: String, body: () -> Unit) { body(); passed++; println("PASS $name") }
    private fun id() = (++number).toString(16).padStart(32, '0')
    private fun rejected(step: QishuiAudioStep, reason: QishuiAudioReason, body: () -> Unit) {
        try { body(); error("Expected rejection") } catch (error: QishuiAudioFailure) {
            check(error.step == step && error.reason == reason) { error.details().toString() }
        }
    }

    @JvmStatic fun main(args: Array<String>) {
        val physical = File(args[0]); val alias = File(args[1]); val outside = File(args[2])
        check(physical.isDirectory && alias.isDirectory && outside.isDirectory)
        val preparation = QishuiOfficialAudioPreparation(physical)
        fun source(id: String, data: ByteArray): File = File(physical, "$id.source").also { it.writeBytes(data) }
        fun prepare(id: String, encrypted: Boolean = false, auth: String = "", cancel: () -> Boolean = { false }) =
            preparation.prepare(id, File(alias, "$id.source").path, File(alias, "$id.m4a").path, encrypted, auth, cancel)

        test("real parent alias resolves to same private directory") {
            check(alias.canonicalFile == physical.canonicalFile)
            val file = source(id(), byteArrayOf(1, 2, 3))
            val alternate = File(alias, file.name)
            check(alternate.absoluteFile != alternate.canonicalFile) { "Fixture must reproduce old path rejection" }
            check(preparation.privateFile(alternate.path, file.name) == file.canonicalFile)
        }
        test("clear preparation through alias returns caller path and exact bytes") {
            val id = id(); val bytes = byteArrayOf(1, 8, 3, 4); source(id, bytes)
            val path = prepare(id)
            check(path == File(alias, "$id.m4a").path && File(path).readBytes().contentEquals(bytes))
        }
        test("canonical caller also works when native root uses alias") {
            val id = id(); val file = source(id, byteArrayOf(1))
            check(QishuiOfficialAudioPreparation(alias).privateFile(file.path, file.name) == file.canonicalFile)
        }
        test("actual CENC preparation through alias produces exact synthetic plaintext") {
            val id = id(); val fixture = QishuiOfficialAudioHostTest.fixture(parts = true)
            source(id, fixture.encoded)
            check(File(prepare(id, true, fixture.auth)).readBytes().contentEquals(fixture.plain))
        }
        test("canonical encrypted caller produces same plaintext") {
            val id = id(); val fixture = QishuiOfficialAudioHostTest.fixture(16)
            val file = source(id, fixture.encoded); val output = File(physical, "$id.m4a")
            preparation.prepare(id, file.path, output.path, true, fixture.auth) { false }
            check(output.readBytes().contentEquals(fixture.plain))
        }
        test("outside source rejected without touching existing output") {
            val id = id(); val external = File(outside, "$id.source").also { it.writeText("outside") }
            rejected(QishuiAudioStep.cachePath, QishuiAudioReason.cachePathInvalid) {
                preparation.prepare(id, external.path, File(alias, "$id.m4a").path, false, "") { false }
            }
            check(external.readText() == "outside")
        }
        test("outside output rejected before writing") {
            val id = id(); source(id, byteArrayOf(2))
            val output = File(outside, "$id.m4a")
            rejected(QishuiAudioStep.cachePath, QishuiAudioReason.cachePathInvalid) {
                preparation.prepare(id, File(alias, "$id.source").path, output.path, false, "") { false }
            }
            check(!output.exists())
        }
        test("parent traversal rejected even if canonical path returns inside") {
            val id = id(); source(id, byteArrayOf(2))
            rejected(QishuiAudioStep.cachePath, QishuiAudioReason.cachePathInvalid) {
                preparation.prepare(id, File(alias, "../${alias.name}/$id.source").path,
                    File(alias, "$id.m4a").path, false, "") { false }
            }
        }
        test("relative source rejected") {
            val id = id()
            rejected(QishuiAudioStep.cachePath, QishuiAudioReason.cachePathInvalid) {
                preparation.prepare(id, "$id.source", File(alias, "$id.m4a").path, false, "") { false }
            }
        }
        test("wrong filename rejected") {
            val id = id(); val file = source(id(), byteArrayOf(3))
            rejected(QishuiAudioStep.cachePath, QishuiAudioReason.cachePathInvalid) {
                preparation.prepare(id, file.path, File(alias, "$id.m4a").path, false, "") { false }
            }
        }
        test("missing source has fixed path-stage reason") {
            rejected(QishuiAudioStep.cachePath, QishuiAudioReason.cacheFileMissing) { prepare(id()) }
        }
        test("existing output is preserved on operation collision") {
            val id = id(); source(id, byteArrayOf(4)); val existing = File(physical, "$id.m4a").also { it.writeText("keep") }
            rejected(QishuiAudioStep.cachePath, QishuiAudioReason.cacheOutputExists) { prepare(id) }
            check(existing.readText() == "keep")
        }
        test("invalid authorization classified before container parse") {
            val id = id(); source(id, byteArrayOf(9))
            rejected(QishuiAudioStep.authorization, QishuiAudioReason.authorizationInvalid) { prepare(id, true, "secret-not-a-key") }
            check(!File(physical, "$id.m4a").exists())
        }
        test("invalid container classified separately from valid authorization") {
            val id = id(); val fixture = QishuiOfficialAudioHostTest.fixture(); source(id, byteArrayOf(9))
            rejected(QishuiAudioStep.containerParse, QishuiAudioReason.mediaStructureUnsupported) { prepare(id, true, fixture.auth) }
        }
        test("unsupported cipher classified separately from malformed container") {
            val id = id(); val fixture = QishuiOfficialAudioHostTest.fixture(); val data = fixture.encoded.copyOf()
            val at = data.toString(Charsets.ISO_8859_1).indexOf("cenc"); "cbcs".toByteArray().copyInto(data, at)
            source(id, data)
            rejected(QishuiAudioStep.containerParse, QishuiAudioReason.encryptionUnsupported) { prepare(id, true, fixture.auth) }
        }
        test("incomplete sample table is a fixed native reason") {
            val id = id(); val fixture = QishuiOfficialAudioHostTest.fixture(invalidCount = true); source(id, fixture.encoded)
            rejected(QishuiAudioStep.containerParse, QishuiAudioReason.sampleTableInvalid) { prepare(id, true, fixture.auth) }
        }
        test("cancellation before preparation never publishes plaintext") {
            val id = id(); source(id, byteArrayOf(1))
            try { prepare(id, cancel = { true }); error("Expected cancellation") } catch (_: CancellationException) { }
            check(!File(physical, "$id.m4a").exists() && File(physical, "$id.source").exists())
        }
        test("cancellation after write removes only this operation output") {
            val id = id(); source(id, byteArrayOf(1)); var checks = 0
            try { prepare(id, cancel = { ++checks >= 4 }); error("Expected cancellation") } catch (_: CancellationException) { }
            check(checks == 4 && !File(physical, "$id.m4a").exists())
        }
        test("unknown native exception text cannot cross bridge") {
            val failure = QishuiAudioFailure.classify(IllegalArgumentException("https://private/?PlayAuth=secret"), QishuiAudioStep.containerParse)
            check(failure.details() == mapOf("step" to "containerParse", "reason" to "mediaStructureUnsupported", "family" to "format"))
            check(!failure.toString().contains("secret"))
        }
        println("QISHUI_PREPARATION_HOST_PASSED=$passed")
    }
}
