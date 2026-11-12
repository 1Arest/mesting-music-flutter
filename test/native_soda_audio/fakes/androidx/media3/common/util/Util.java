package androidx.media3.common.util;
/** Isolates Android platform initialization in Media3's utility class. The
 * AudioProcessor/AudioFormat/BaseAudioProcessor classes come from the actual
 * cached Media3 AAR; particularly EMPTY_BUFFER and output ownership are real. */
public final class Util {
    public static boolean isEncodingLinearPcm(int e) { return e == 2 || e == 4; }
    public static int getPcmFrameSize(int e, int channels) { return channels * (e == 2 ? 2 : 4); }
}
