package com.mesting.music

import java.io.File
import java.io.IOException
import java.util.concurrent.CancellationException

/** Closed bridge vocabulary: never send exception text, paths or PlayAuth to Dart. */
enum class QishuiAudioStep { cachePath, sourceRead, authorization, containerParse, sampleDecrypt, cacheWrite, metadataRead }

enum class QishuiAudioReason {
    cachePathInvalid, cacheFileMissing, cacheOutputExists, sourceReadFailed,
    authorizationInvalid, mediaStructureUnsupported, encryptionUnsupported,
    sampleTableInvalid, sampleDecryptFailed, cacheWriteFailed, metadataUnsupported,
    operationInvalid, bridgeUnavailable, unknown
}

class QishuiAudioFailure(
    val step: QishuiAudioStep,
    val reason: QishuiAudioReason,
    val family: String,
) : Exception("Official media operation failed") {
    fun details(): Map<String, String> = mapOf("step" to step.name, "reason" to reason.name, "family" to family)

    companion object {
        fun classify(error: Throwable, step: QishuiAudioStep): QishuiAudioFailure {
            if (error is QishuiAudioFailure) return error
            // Compare only known internal validation labels. Unknown messages
            // never become diagnostic fields, even for a platform/codec error.
            val reason = when (step) {
                QishuiAudioStep.cachePath -> when (error.message) {
                    "path_missing", "source_missing" -> QishuiAudioReason.cacheFileMissing
                    "output_exists" -> QishuiAudioReason.cacheOutputExists
                    "operation_id" -> QishuiAudioReason.operationInvalid
                    else -> QishuiAudioReason.cachePathInvalid
                }
                QishuiAudioStep.sourceRead -> QishuiAudioReason.sourceReadFailed
                QishuiAudioStep.authorization -> QishuiAudioReason.authorizationInvalid
                QishuiAudioStep.containerParse -> when (error.message) {
                    "encryption_scheme", "encryption_info_version", "encryption_iv_size", "original_codec" ->
                        QishuiAudioReason.encryptionUnsupported
                    "sample_sizes_missing", "sample_sizes_incomplete", "sample_sizes_truncated",
                    "sample_sizes_count", "sample_size_invalid", "sample_encryption_missing",
                    "sample_encryption_truncated", "sample_encryption_version", "sample_encryption_count",
                    "sample_iv_truncated", "sample_parts_truncated", "sample_parts_size", "sample_parts_incomplete",
                    "sample_encryption_trailing" -> QishuiAudioReason.sampleTableInvalid
                    else -> QishuiAudioReason.mediaStructureUnsupported
                }
                QishuiAudioStep.sampleDecrypt -> QishuiAudioReason.sampleDecryptFailed
                QishuiAudioStep.cacheWrite -> QishuiAudioReason.cacheWriteFailed
                QishuiAudioStep.metadataRead -> QishuiAudioReason.metadataUnsupported
            }
            val family = when {
                error is IOException -> "io"
                step == QishuiAudioStep.authorization || step == QishuiAudioStep.sampleDecrypt -> "decrypt"
                else -> "format"
            }
            return QishuiAudioFailure(step, reason, family)
        }
    }
}

/** Android-free production boundary, also exercised with real host files.
 *
 * An Android cache directory can have multiple spellings (/data/user/0 and
 * /data/data). Resolve its parent before enforcing containment; comparing the
 * entire unnormalised path to its canonical form rejects legitimate aliases.
 * Leaf links, traversal, wrong names and escapes remain forbidden.
 */
class QishuiOfficialAudioPreparation(root: File) {
    private val root = root.canonicalFile

    fun privateFile(path: String?, exactName: String? = null, requireExists: Boolean = true): File {
        require(path != null) { "path_missing" }
        val file = File(path)
        require(file.isAbsolute && file.path.split(File.separatorChar).none { it == ".." }) { "path_invalid" }
        require(if (exactName == null) OUTPUT.matches(file.name) else file.name == exactName) { "path_name" }
        val canonical = file.canonicalFile
        require(file.parentFile?.canonicalFile == root && canonical == File(root, file.name)) {
            "path_outside_private_cache"
        }
        if (requireExists) require(canonical.isFile) { "source_missing" }
        return canonical
    }

    fun prepare(
        id: String?, sourcePath: String?, outputPath: String?, encrypted: Boolean,
        playAuth: String, cancelled: () -> Boolean,
    ): String {
        var step = QishuiAudioStep.cachePath
        var output: File? = null
        var ownsOutput = false
        fun checkCancelled() {
            if (cancelled() || Thread.currentThread().isInterrupted) throw CancellationException("cancelled")
        }
        try {
            checkCancelled()
            require(id != null && ID.matches(id)) { "operation_id" }
            val source = privateFile(sourcePath, "$id.source")
            output = privateFile(outputPath, "$id.m4a", requireExists = false)
            require(!output.exists()) { "output_exists" }
            step = QishuiAudioStep.sourceRead
            require(source.length() in 1..QishuiOfficialAudioDecrypt.MAX_FILE_BYTES.toLong()) { "media_size" }
            val encoded = source.readBytes()
            checkCancelled()
            val plain = if (encrypted) {
                QishuiOfficialAudioDecrypt.decryptAudio(encoded, playAuth, onStep = { step = it }, cancelled = cancelled)
            } else encoded
            checkCancelled()
            step = QishuiAudioStep.cacheWrite
            // Create atomically: failure must not remove an older file that
            // another operation owns, even if a name unexpectedly collides.
            require(output.createNewFile()) { "output_exists" }
            ownsOutput = true
            output.outputStream().use { it.write(plain); it.flush() }
            checkCancelled()
            // Dart owns the supplied path. Return its original valid alias,
            // while all native I/O uses the canonical, contained file.
            return outputPath!!
        } catch (error: Throwable) {
            if (ownsOutput) runCatching { output?.delete() }
            if (error is CancellationException) throw error
            throw QishuiAudioFailure.classify(error, step)
        }
    }

    private companion object {
        val ID = Regex("^[0-9a-f]{32}$")
        val OUTPUT = Regex("^[0-9a-f]{32}\\.m4a$")
    }
}
