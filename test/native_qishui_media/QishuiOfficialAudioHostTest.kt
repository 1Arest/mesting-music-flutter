import com.mesting.music.QishuiOfficialAudioDecrypt
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Base64
import java.util.concurrent.CancellationException
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Synthetic bytes only: no real account, media URL, or captured PlayAuth. */
object QishuiOfficialAudioHostTest {
    private var passed = 0
    private val key = ByteArray(16) { (it * 7 + 3).toByte() }
    private fun test(name: String, body: () -> Unit) { body(); passed++; println("PASS $name") }
    private fun fail(body: () -> Unit) {
        try { body(); error("Expected rejection") } catch (_: IllegalArgumentException) { }
    }
    private fun n32(n: Int) = byteArrayOf((n ushr 24).toByte(), (n ushr 16).toByte(), (n ushr 8).toByte(), n.toByte())
    private fun box(name: String, vararg parts: ByteArray): ByteArray {
        val body = parts.fold(ByteArray(0)) { a, b -> a + b }
        return n32(body.size + 8) + name.toByteArray() + body
    }
    private fun envelope(): String {
        val hex = key.joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val plain = ("0" + hex).toByteArray()
        val inner = ByteArray(plain.size)
        for (i in plain.indices) {
            val previous = when (i) { 0 -> 0xfa; 1 -> 0x55; else -> inner[i - 2].toInt() and 0xff }
            inner[i] = ((plain[i].toInt() + Integer.bitCount(i) + 21) xor previous).toByte()
        }
        val first = (inner[0].toInt() and 0xff) xor (inner[1].toInt() and 0xff) xor 48
        return Base64.getEncoder().encodeToString(byteArrayOf(first.toByte()) + inner)
    }
    internal data class Fixture(val encoded: ByteArray, val plain: ByteArray, val auth: String)
    internal fun fixture(ivSize: Int = 8, parts: Boolean = false, invalidCount: Boolean = false): Fixture {
        val plain = ByteArray(87) { (it * 13 + 4).toByte() }
        val iv = ByteArray(ivSize) { (it * 3 + 1).toByte() }
        val cipher = Cipher.getInstance("AES/CTR/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv.copyOf(16)))
        val encoded = if (parts) plain.copyOf().also { dest ->
            cipher.update(plain, 5, 30).copyInto(dest, 5)
            cipher.update(plain, 39, 48).copyInto(dest, 39)
            check(cipher.doFinal().isEmpty())
        } else cipher.doFinal(plain)
        val protection = box("sinf", box("frma", "mp4a".toByteArray()),
            box("schm", n32(0), "cenc".toByteArray(), n32(0)),
            box("schi", box("tenc", n32(0), byteArrayOf(0, 0, 1, ivSize.toByte()), ByteArray(16))))
        val entry = box("enca", ByteArray(28), protection)
        val stsd = box("stsd", n32(0), n32(1), entry)
        val stsz = box("stsz", n32(0), n32(0), n32(if (invalidCount) 2 else 1), n32(87))
        val senc = box("senc", n32(if (parts) 2 else 0), n32(1), iv,
            if (parts) byteArrayOf(0, 2, 0, 5) + n32(30) + byteArrayOf(0, 4) + n32(48) else ByteArray(0))
        val moov = box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd, stsz, senc)))))
        val file = box("ftyp", "M4A ".toByteArray(), n32(0)) + moov + box("mdat", encoded)
        val expected = file.copyOf()
        plain.copyInto(expected, expected.size - plain.size)
        val encaAt = expected.toString(Charsets.ISO_8859_1).indexOf("enca")
        "mp4a".toByteArray().copyInto(expected, encaAt)
        return Fixture(file, expected, envelope())
    }

    @JvmStatic fun main(args: Array<String>) {
        if (args.size == 3 && args[0] == "--decode-private") {
            // Explicit private research only. No key or authorization output.
            val manifest = File(args[1]).readLines()
            File(args[2]).writeBytes(QishuiOfficialAudioDecrypt.decryptAudio(File(manifest[0]).readBytes(), manifest[1]))
            println("PRIVATE_DECODE_OK")
            return
        }
        test("8-byte IV synthetic full sample decodes exact bytes") {
            val f = fixture(); check(QishuiOfficialAudioDecrypt.decryptAudio(f.encoded, f.auth).contentEquals(f.plain))
        }
        test("16-byte IV exact bytes") {
            val f = fixture(16); check(QishuiOfficialAudioDecrypt.decryptAudio(f.encoded, f.auth).contentEquals(f.plain))
        }
        test("subsample clear ranges do not consume cipher counter") {
            val f = fixture(parts = true); check(QishuiOfficialAudioDecrypt.decryptAudio(f.encoded, f.auth).contentEquals(f.plain))
        }
        test("truncated declared sample table rejects") {
            val f = fixture(invalidCount = true); fail { QishuiOfficialAudioDecrypt.decryptAudio(f.encoded, f.auth) }
        }
        test("truncated MP4 box rejects") {
            val f = fixture(); fail { QishuiOfficialAudioDecrypt.decryptAudio(f.encoded.copyOf(f.encoded.size - 1), f.auth) }
        }
        test("invalid authorization rejects") { fail { QishuiOfficialAudioDecrypt.decryptAudio(fixture().encoded, "not-a-key") } }
        test("unknown scheme rejects") {
            val f = fixture(); val data = f.encoded.copyOf()
            val at = data.toString(Charsets.ISO_8859_1).indexOf("cenc")
            "cbcs".toByteArray().copyInto(data, at)
            fail { QishuiOfficialAudioDecrypt.decryptAudio(data, f.auth) }
        }
        test("missing sample encryption never passes ciphertext through") {
            val f = fixture(); val data = f.encoded.copyOf()
            val at = data.toString(Charsets.ISO_8859_1).indexOf("senc")
            "free".toByteArray().copyInto(data, at)
            fail { QishuiOfficialAudioDecrypt.decryptAudio(data, f.auth) }
        }
        test("subsample size overflow rejects") {
            val f = fixture(parts = true); val data = f.encoded.copyOf()
            val at = data.toString(Charsets.ISO_8859_1).indexOf("senc")
            n32(Int.MAX_VALUE).copyInto(data, at + 24)
            fail { QishuiOfficialAudioDecrypt.decryptAudio(data, f.auth) }
        }
        test("cancellation before plaintext publication") {
            val f = fixture()
            try { QishuiOfficialAudioDecrypt.decryptAudio(f.encoded, f.auth) { true }; error("Expected cancellation") }
            catch (_: CancellationException) { }
        }
        println("QISHUI_CENC_HOST_PASSED=$passed")
    }
}
