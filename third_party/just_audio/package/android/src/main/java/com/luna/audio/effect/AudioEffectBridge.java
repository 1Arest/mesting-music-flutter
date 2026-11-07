package com.luna.audio.effect;

import android.content.Context;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.nio.ByteBuffer;

/** Minimal declarations matching the pinned binary's exported JNI ABI.
 * No host hooks, entitlement overrides, logging framework or extra native
 * entrypoints are copied. Loaded lazily and only for an explicit DSP request.
 */
@androidx.annotation.Keep
public final class AudioEffectBridge {
    private static boolean loaded;
    /** Pinned proprietary binaries have 4KiB ELF segments. Keep them out of
     * Android's app-wide JNI directory and load only on a compatible process,
     * after an explicit user request. Originals stay byte-identical in assets.
     * The fixed hashes and private versioned directory are not configurable.
     */
    public static synchronized void initialize(Context context) throws Exception {
        if (loaded) return;
        File directory = new File(context.getCodeCacheDir(), "soda-dsp-b639e67c13e03377");
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("DSP cache unavailable");
        String[][] libraries = {
            {"libc++_shared.so", "e8373ee43274541efd2d34fe0588d55bf953612e1417ad47cfd2c4bd1aa383d0"},
            {"libBYTE_AUDIO_TUNER_CAPI_LITE.so", "6809019c6e9436a1770873030fbec9fa94686802cd84ecfe52e5312e36bda36c"},
            {"libaudio_effect_bridge.so", "d1721a8a9032b31e0857f692e15dedc8b5003486cfb070d519d9808a2100dbfd"},
        };
        for (String[] library : libraries) {
            File file = new File(directory, library[0]);
            if (file.exists()) {
                // Never truncate a file another engine/process has loaded.
                // A partial earlier extraction cannot become an executable.
                MessageDigest existing = MessageDigest.getInstance("SHA-256");
                try (InputStream input = new FileInputStream(file)) {
                    byte[] bytes = new byte[16384]; int count;
                    while ((count = input.read(bytes)) != -1) existing.update(bytes, 0, count);
                }
                if (!library[1].equals(hex(existing.digest()))) throw new IOException("DSP cache integrity failed");
                System.load(file.getAbsolutePath());
                continue;
            }
            // Extraction is synchronized and private to this app. Re-read the
            // packaged asset only when no verified cached file exists; no external
            // download, path import or server-delivered native code is used.
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            File temporary = new File(directory, library[0] + "." + android.os.Process.myPid() + ".pending");
            try (InputStream input = context.getAssets().open(
                    "flutter_assets/third_party/qishui_effects/arm64-v8a/" + library[0]);
                 FileOutputStream output = new FileOutputStream(temporary)) {
                byte[] buffer = new byte[16384];
                int count, total = 0;
                while ((count = input.read(buffer)) != -1) {
                    total += count;
                    if (total > 2 * 1024 * 1024) throw new IOException("DSP asset too large");
                    digest.update(buffer, 0, count);
                    output.write(buffer, 0, count);
                }
                output.getFD().sync();
            }
            if (!library[1].equals(hex(digest.digest()))) throw new IOException("DSP asset integrity failed");
            if (!temporary.renameTo(file)) throw new IOException("DSP cache commit failed");
            System.load(file.getAbsolutePath());
        }
        loaded = true;
    }
    private static String hex(byte[] bytes) {
        StringBuilder value = new StringBuilder();
        for (byte b : bytes) value.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
        return value.toString();
    }
    private AudioEffectBridge() {}
    public static native int isValidConfigJson(String json);
    public static native long createEffectHandleByConfig(int samples, int sampleRate, int channels, String json);
    public static native long createAudioBuffer(long handle, int samples, int sampleRate, int channels);
    public static native int processAudio(ByteBuffer[] planar, long handle, long buffer,
        int sampleRate, int samples, int channels, int format);
    public static native void release(long handle);
}
