package com.ryanheise.just_audio;

import android.os.Build;
import android.content.Context;
import android.system.Os;
import android.system.OsConstants;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import com.luna.audio.effect.AudioEffectBridge;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.Map;

/** Per-player PCM processor. Only Media3's audio thread owns native handles.
 * Control requests publish immutable configurations; flush/release run on the
 * same renderer lifecycle as decoding. No second player or system EQ is used.
 *
 * The binary takes planar float32, not interleaved PCM16. Fixed-size blocks
 * bound allocations and the native frame contract. A short EOS block is padded
 * for the engine and cropped back, without lengthening the audible stream.
 */
public final class SodaAudioProcessor extends BaseAudioProcessor {
    private static final int FRAMES = 512;
    private final Context context;
    public SodaAudioProcessor(Context context) { this.context = context.getApplicationContext(); }
    private volatile Configuration requested = new Configuration(0, null);
    private volatile long processedFrames;
    private volatile String failure = "";
    private volatile boolean available;
    private long generation = -1, handle, nativeBuffer;
    private ByteBuffer pending;
    private ByteBuffer[] planar;

    private static final class Configuration {
        final long generation;
        final String json;
        Configuration(long generation, String json) { this.generation = generation; this.json = json; }
    }

    /** Called by the owner channel, never with credentials or arbitrary paths. */
    public synchronized Map<String, Object> select(String json) {
        if (json == null || json.isEmpty()) {
            requested = new Configuration(requested.generation + 1, null);
            return status();
        }
        boolean arm64 = false;
        for (String abi : Build.SUPPORTED_ABIS) if ("arm64-v8a".equals(abi)) arm64 = true;
        if (!arm64 || !android.os.Process.is64Bit()) { failure = "unsupported_abi"; return status(); }
        try {
            if (Os.sysconf(OsConstants._SC_PAGESIZE) != 4096) {
                failure = "unsupported_page_size";
                return status();
            }
            AudioEffectBridge.initialize(context);
            if (json.length() > 256 * 1024 || AudioEffectBridge.isValidConfigJson(json) != 0) {
                failure = "invalid_config";
                return status();
            }
            available = true;
            failure = "";
            processedFrames = 0;
            requested = new Configuration(requested.generation + 1, json);
        } catch (LinkageError | Exception error) {
            // Never expose a raw native error or let a missing ARM32 library
            // interrupt ordinary playback on the same installation.
            available = false;
            failure = "native_unavailable";
        }
        return status();
    }

    public Map<String, Object> status() {
        Map<String, Object> result = new HashMap<>();
        result.put("available", available);
        result.put("configured", requested.json != null);
        result.put("processedFrames", processedFrames);
        result.put("failure", failure);
        return result;
    }

    @Override
    protected AudioFormat onConfigure(AudioFormat format) {
        if (format.channelCount < 1 || format.channelCount > 2 ||
            (format.encoding != C.ENCODING_PCM_16BIT && format.encoding != C.ENCODING_PCM_FLOAT)) {
            if (requested.json != null) failure = "unsupported_pcm";
            return AudioFormat.NOT_SET;
        }
        return format;
    }

    private void releaseHandle() {
        if (handle > 0) {
            try { AudioEffectBridge.release(handle); }
            catch (LinkageError | RuntimeException error) { failure = "release_failed"; }
        }
        handle = nativeBuffer = 0;
    }

    private void apply(Configuration next) {
        releaseHandle();
        generation = next.generation;
        if (pending == null || pending.capacity() != FRAMES * inputAudioFormat.bytesPerFrame) {
            pending = ByteBuffer.allocateDirect(FRAMES * inputAudioFormat.bytesPerFrame).order(ByteOrder.LITTLE_ENDIAN);
            planar = new ByteBuffer[inputAudioFormat.channelCount];
            for (int i = 0; i < planar.length; i++) {
                planar[i] = ByteBuffer.allocateDirect(FRAMES * 4).order(ByteOrder.LITTLE_ENDIAN);
            }
        }
        if (next.json == null) return;
        try {
            handle = AudioEffectBridge.createEffectHandleByConfig(FRAMES,
                inputAudioFormat.sampleRate, inputAudioFormat.channelCount, next.json);
            if (handle < 65536 || (handle & 7L) != 0) { handle = 0; failure = "create_failed"; return; }
            nativeBuffer = AudioEffectBridge.createAudioBuffer(handle, FRAMES,
                inputAudioFormat.sampleRate, inputAudioFormat.channelCount);
            if (nativeBuffer < 65536 || (nativeBuffer & 7L) != 0) { releaseHandle(); failure = "buffer_failed"; }
        } catch (LinkageError | RuntimeException error) {
            releaseHandle(); failure = "native_unavailable";
        }
    }

    /** Original bytes remain in pending until processing succeeds, allowing
     * exact bypass on an error. Nonfinite/out-of-range samples are bounded. */
    private void emitBlock(ByteBuffer output, int validBytes) {
        pending.flip();
        if (handle <= 0 || nativeBuffer <= 0) {
            for (int i = 0; i < validBytes; i++) output.put(pending.get(i));
            pending.clear(); return;
        }
        final int channels = inputAudioFormat.channelCount;
        final boolean pcm16 = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT;
        for (ByteBuffer plane : planar) plane.clear();
        for (int f = 0; f < FRAMES; f++) {
            for (int c = 0; c < channels; c++) {
                float sample = pcm16 ? pending.getShort() / 32768.0f : pending.getFloat();
                planar[c].putFloat(Float.isFinite(sample) ? sample : 0f);
            }
        }
        boolean ok;
        try {
            // format is unused by this bridge implementation; 4-byte planes
            // are explicitly supplied regardless of Media3's input format.
            ok = AudioEffectBridge.processAudio(planar, handle, nativeBuffer,
                inputAudioFormat.sampleRate, FRAMES, channels, 0) == 0;
        } catch (LinkageError | RuntimeException error) { ok = false; }
        if (!ok) {
            failure = "process_failed";
            for (int i = 0; i < validBytes; i++) output.put(pending.get(i));
            releaseHandle();
        } else {
            for (ByteBuffer plane : planar) plane.rewind();
            final int frames = validBytes / inputAudioFormat.bytesPerFrame;
            for (int f = 0; f < frames; f++) {
                for (int c = 0; c < channels; c++) {
                    float sample = planar[c].getFloat();
                    sample = Float.isFinite(sample) ? Math.max(-1f, Math.min(1f, sample)) : 0f;
                    if (pcm16) output.putShort((short)Math.round(sample < 0 ? sample * 32768f : sample * 32767f));
                    else output.putFloat(sample);
                }
            }
            processedFrames += frames;
        }
        pending.clear();
    }

    @Override
    public void queueInput(ByteBuffer input) {
        Configuration next = requested;
        if (generation != next.generation || pending == null) apply(next);
        // An ordinary non-Soda stream incurs only a direct pass-through copy.
        // Drain an already buffered partial block before changing config.
        if (next.json == null && pending.position() == 0) {
            ByteBuffer output = replaceOutputBuffer(input.remaining());
            output.put(input).flip(); return;
        }
        int bytes = input.remaining() + pending.position();
        ByteBuffer output = replaceOutputBuffer(bytes).order(ByteOrder.LITTLE_ENDIAN);
        while (input.hasRemaining()) {
            int amount = Math.min(input.remaining(), pending.remaining());
            int oldLimit = input.limit();
            input.limit(input.position() + amount); pending.put(input); input.limit(oldLimit);
            if (!pending.hasRemaining()) emitBlock(output, pending.capacity());
        }
        output.flip();
    }

    @Override
    protected void onQueueEndOfStream() {
        if (pending == null || pending.position() == 0) return;
        int valid = pending.position();
        while (pending.hasRemaining()) pending.put((byte)0);
        ByteBuffer output = replaceOutputBuffer(valid).order(ByteOrder.LITTLE_ENDIAN);
        emitBlock(output, valid); output.flip();
    }
    @Override
    @SuppressWarnings("deprecation")
    protected void onFlush() { releaseHandle(); generation = -1; if (pending != null) pending.clear(); }
    @Override
    protected void onReset() { onFlush(); pending = null; planar = null; }
}
