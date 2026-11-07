package com.mesting.music

import java.util.concurrent.CancellationException
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Whole-file official CENC audio adapter, derived from myMusic SodaDecrypt.kt
 * at 9c0f1f0ccb1b1046306f61c50998e327c040a6bc (AGPL-3.0).
 * See third_party/qishui_official_media/NOTICE.md and its preserved license.
 *
 * This consumes only the PlayAuth returned for the user's authorized stream.
 * It does not obtain media rights, sign a request, recover a missing key, or
 * accept another account's cached authorization. No key or PlayAuth is logged.
 * Unsupported/partial MP4s fail before publishing a playable file.
 *
 * The parser is Android-free so malformed-table and synthetic cryptographic
 * fixtures run against this production code on the JVM.
 */
object QishuiOfficialAudioDecrypt {
    const val MAX_FILE_BYTES = 128 * 1024 * 1024
    private const val MAX_SAMPLES = 1_000_000
    private const val BLOCK_SIZE = 16

    fun decryptAudio(
        data: ByteArray,
        playAuth: String,
        cancelled: () -> Boolean = { false },
    ): ByteArray {
        require(data.isNotEmpty() && data.size <= MAX_FILE_BYTES) { "media_size" }
        checkCancelled(cancelled)
        val key = authorizedKey(playAuth)
        try {
            val top = boxes(data, 0, data.size)
            require(top.none { it.type == "moof" }) { "fragmented_media" }
            require(top.count { it.type == "moov" } == 1 && top.count { it.type == "mdat" } == 1) {
                "media_layout"
            }
            val moov = top.single { it.type == "moov" }
            val mdat = top.single { it.type == "mdat" }
            val tables = descendants(data, moov, "stbl")
            require(tables.size == 1) { "media_track_count" }
            val table = tables.single()
            val tableBoxes = boxes(data, table.dataStart, table.end)
            val stsz = tableBoxes.singleOrNull { it.type == "stsz" }
                ?: throw IllegalArgumentException("sample_sizes_missing")
            val sizes = sampleSizes(data, stsz)
            require(sizes.sumOf { it.toLong() } == (mdat.end - mdat.dataStart).toLong()) {
                "sample_sizes_incomplete"
            }
            val descriptions = descendants(data, table, "enca")
            require(descriptions.size == 1) { "encrypted_codec_missing" }
            val description = descriptions.single()
            val schemes = descendants(data, description, "schm")
            require(schemes.size <= 1) { "encryption_scheme" }
            schemes.singleOrNull()?.let {
                require(it.dataStart + 8 <= it.end && text(data, it.dataStart + 4) == "cenc") {
                    "encryption_scheme"
                }
            }
            val tenc = descendants(data, description, "tenc").singleOrNull()
                ?: throw IllegalArgumentException("encryption_info_missing")
            require(tenc.dataStart + 24 == tenc.end && data[tenc.dataStart].toInt() == 0) {
                "encryption_info_version"
            }
            // Pinned official version-0 tenc: FullBox(4), algorithm/protection
            // bytes(00 00 01), per-sample IV size, 16-byte KID. This exact
            // layout was checked against the authorized anonymous media bytes.
            require(data[tenc.dataStart + 4].toInt() == 0 && data[tenc.dataStart + 5].toInt() == 0 &&
                (data[tenc.dataStart + 6].toInt() and 0xff) == 1) { "encryption_info" }
            val ivSize = data[tenc.dataStart + 7].toInt() and 0xff
            require(ivSize == 8 || ivSize == 16) { "encryption_iv_size" }
            val sencs = descendants(data, moov, "senc")
            require(sencs.size == 1) { "sample_encryption_missing" }
            val samples = sampleEncryption(data, sencs.single(), ivSize, sizes)
            val original = descendants(data, description, "frma").singleOrNull()
                ?: throw IllegalArgumentException("original_codec_missing")
            require(original.dataStart + 4 <= original.end) { "original_codec" }
            val codec = text(data, original.dataStart)
            require(codec in setOf("mp4a", "fLaC", "alac")) { "original_codec" }

            val result = data.copyOf()
            var offset = mdat.dataStart
            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            val secret = SecretKeySpec(key, "AES")
            for (index in sizes.indices) {
                checkCancelled(cancelled)
                val sample = samples[index]
                val iv = ByteArray(BLOCK_SIZE)
                sample.iv.copyInto(iv)
                cipher.init(Cipher.DECRYPT_MODE, secret, IvParameterSpec(iv))
                if (sample.parts.isEmpty()) {
                    cipher.doFinal(data, offset, sizes[index]).copyInto(result, offset)
                } else {
                    // CENC clear ranges do not consume counter bytes. Feed all
                    // encrypted ranges through the same per-sample CTR state.
                    var at = offset
                    for (part in sample.parts) {
                        at += part.clear
                        if (part.encrypted > 0) {
                            cipher.update(data, at, part.encrypted).copyInto(result, at)
                        }
                        at += part.encrypted
                    }
                    require(cipher.doFinal().isEmpty()) { "sample_cipher_tail" }
                }
                offset += sizes[index]
            }
            codec.toByteArray(Charsets.ISO_8859_1).copyInto(result, description.start + 4)
            checkCancelled(cancelled)
            return result
        } finally {
            key.fill(0)
        }
    }

    /** Spade envelope transform from the attributed source; no fallback key. */
    private fun authorizedKey(playAuth: String): ByteArray {
        require(playAuth.isNotBlank() && playAuth.length <= 8192) { "authorization_missing" }
        val envelope = decodeBase64(playAuth)
        require(envelope.size >= 3) { "authorization_invalid" }
        val padding = ((envelope[0].toInt() and 0xff) xor
            (envelope[1].toInt() and 0xff) xor (envelope[2].toInt() and 0xff)) - 48
        require(padding >= 0 && padding < envelope.size - 2) { "authorization_invalid" }
        val inner = envelope.copyOfRange(1, envelope.size - padding)
        val decoded = ByteArray(inner.size)
        try {
            for (i in inner.indices) {
                val previous = when (i) {
                    0 -> 0xfa
                    1 -> 0x55
                    else -> inner[i - 2].toInt() and 0xff
                }
                var value = ((inner[i].toInt() and 0xff) xor previous) - Integer.bitCount(i) - 21
                while (value < 0) value += 255
                decoded[i] = value.toByte()
            }
            val skip = (decoded[0].toInt() and 0xff).toChar().digitToIntOrNull(36)
                ?: throw IllegalArgumentException("authorization_invalid")
            val end = envelope.size - padding - 1 - skip
            require(end > 1 && end <= decoded.size && end - 1 == BLOCK_SIZE * 2) {
                "authorization_key_length"
            }
            return ByteArray(BLOCK_SIZE) { i ->
                val high = (decoded[1 + i * 2].toInt() and 0xff).toChar().digitToIntOrNull(16)
                val low = (decoded[2 + i * 2].toInt() and 0xff).toChar().digitToIntOrNull(16)
                require(high != null && low != null) { "authorization_key_format" }
                ((high shl 4) or low).toByte()
            }
        } finally {
            envelope.fill(0)
            inner.fill(0)
            decoded.fill(0)
        }
    }

    // java.util.Base64 is API 26; the app still supports Android 24/25. Keep
    // this tiny standard decoder Android-free and reject malformed input.
    private fun decodeBase64(input: String): ByteArray {
        val clean = input.filterNot { it.isWhitespace() }
        require(clean.length % 4 != 1) { "authorization_invalid" }
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        val output = ByteArray(clean.length * 3 / 4 + 3)
        var accumulator = 0
        var bits = 0
        var count = 0
        var padding = 0
        for (c in clean) {
            if (c == '=') {
                padding++
                require(padding <= 2) { "authorization_invalid" }
                continue
            }
            val digit = alphabet.indexOf(c)
            require(digit >= 0 && padding == 0) { "authorization_invalid" }
            accumulator = (accumulator shl 6) or digit
            bits += 6
            if (bits >= 8) {
                bits -= 8
                output[count++] = (accumulator ushr bits).toByte()
            }
        }
        require((padding == 0 || clean.length % 4 == 0) &&
            (bits == 0 || accumulator and ((1 shl bits) - 1) == 0)) { "authorization_invalid" }
        return output.copyOf(count)
    }

    private fun sampleSizes(data: ByteArray, box: Box): IntArray {
        val at = box.dataStart
        require(at + 12 <= box.end) { "sample_sizes_truncated" }
        val fixed = u32(data, at + 4)
        val count = u32(data, at + 8)
        require(count in 1..MAX_SAMPLES.toLong() && fixed <= data.size) { "sample_sizes_count" }
        if (fixed == 0L) require(at + 12L + count * 4 <= box.end) { "sample_sizes_truncated" }
        return IntArray(count.toInt()) { index ->
            val size = if (fixed == 0L) u32(data, at + 12 + index * 4) else fixed
            require(size in 1..data.size.toLong()) { "sample_size_invalid" }
            size.toInt()
        }
    }

    private fun sampleEncryption(data: ByteArray, box: Box, ivSize: Int, sizes: IntArray): List<Sample> {
        val start = box.dataStart
        require(start + 8 <= box.end) { "sample_encryption_truncated" }
        val flags = u32(data, start)
        require(flags == 0L || flags == 2L) { "sample_encryption_version" }
        require(u32(data, start + 4) == sizes.size.toLong()) { "sample_encryption_count" }
        val result = ArrayList<Sample>(sizes.size)
        var at = start + 8
        for (size in sizes) {
            require(at + ivSize <= box.end) { "sample_iv_truncated" }
            val iv = data.copyOfRange(at, at + ivSize)
            at += ivSize
            val parts = ArrayList<Part>()
            if (flags == 2L) {
                require(at + 2 <= box.end) { "sample_parts_truncated" }
                val count = u16(data, at)
                at += 2
                require(at + count.toLong() * 6 <= box.end) { "sample_parts_truncated" }
                var declared = 0L
                repeat(count) {
                    val clear = u16(data, at)
                    val encrypted = u32(data, at + 2)
                    require(encrypted <= size && declared + clear + encrypted <= size) { "sample_parts_size" }
                    parts.add(Part(clear, encrypted.toInt()))
                    declared += clear + encrypted
                    at += 6
                }
                require(parts.isEmpty() || declared == size.toLong()) { "sample_parts_incomplete" }
            }
            result.add(Sample(iv, parts))
        }
        require(at == box.end) { "sample_encryption_trailing" }
        return result
    }

    private data class Box(val start: Int, val dataStart: Int, val end: Int, val type: String)
    private data class Part(val clear: Int, val encrypted: Int)
    private data class Sample(val iv: ByteArray, val parts: List<Part>)

    private fun boxes(data: ByteArray, start: Int, end: Int): List<Box> {
        require(start >= 0 && end <= data.size && start <= end) { "box_bounds" }
        val result = ArrayList<Box>()
        var at = start
        while (at < end) {
            require(at.toLong() + 8 <= end) { "box_header_truncated" }
            var size = u32(data, at)
            var header = 8
            if (size == 1L) {
                require(at.toLong() + 16 <= end) { "box_header_truncated" }
                size = u64(data, at + 8)
                header = 16
            } else if (size == 0L) {
                size = (end - at).toLong()
            }
            require(size >= header && size <= end.toLong() - at) { "box_size_invalid" }
            require(result.size < MAX_SAMPLES) { "box_count" }
            result.add(Box(at, at + header, at + size.toInt(), text(data, at + 4)))
            at += size.toInt()
        }
        return result
    }

    private fun descendants(data: ByteArray, root: Box, wanted: String, depth: Int = 0): List<Box> {
        require(depth <= 12) { "box_depth" }
        val start = when (root.type) {
            "moov", "trak", "mdia", "minf", "stbl", "sinf", "schi" -> root.dataStart
            "stsd" -> root.dataStart + 8
            "enca", "mp4a", "fLaC", "alac" -> root.dataStart + 28
            else -> return emptyList()
        }
        require(start <= root.end) { "box_children_truncated" }
        return boxes(data, start, root.end).flatMap {
            (if (it.type == wanted) listOf(it) else emptyList()) + descendants(data, it, wanted, depth + 1)
        }
    }

    private fun text(data: ByteArray, at: Int) = String(data, at, 4, Charsets.ISO_8859_1)
    private fun u16(data: ByteArray, at: Int): Int =
        ((data[at].toInt() and 0xff) shl 8) or (data[at + 1].toInt() and 0xff)
    private fun u32(data: ByteArray, at: Int): Long =
        ((data[at].toLong() and 0xff) shl 24) or ((data[at + 1].toLong() and 0xff) shl 16) or
            ((data[at + 2].toLong() and 0xff) shl 8) or (data[at + 3].toLong() and 0xff)
    private fun u64(data: ByteArray, at: Int): Long {
        val high = u32(data, at)
        require(high <= 0x7fffffffL) { "box_size_invalid" }
        return (high shl 32) or u32(data, at + 4)
    }
    private fun checkCancelled(cancelled: () -> Boolean) {
        if (cancelled() || Thread.currentThread().isInterrupted) throw CancellationException("cancelled")
    }
}
