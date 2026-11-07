package com.luna.audio.effect;
import android.content.Context;
import java.nio.ByteBuffer;
/** No device or proprietary native binary is loaded by host regression tests. */
public final class AudioEffectBridge {
    public static boolean failCreate;
    public static int releases;
    public static void initialize(Context c) {}
    public static int isValidConfigJson(String json) { return 0; }
    public static long createEffectHandleByConfig(int n, int hz, int channels, String json) {
        return failCreate ? 0 : 65536;
    }
    public static long createAudioBuffer(long handle, int n, int hz, int channels) { return 131072; }
    public static int processAudio(ByteBuffer[] planes, long handle, long buffer, int hz, int n, int c, int f) { return 0; }
    public static void release(long handle) { releases++; }
}
