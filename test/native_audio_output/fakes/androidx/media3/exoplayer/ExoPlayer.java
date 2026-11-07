package androidx.media3.exoplayer;
import android.media.AudioDeviceInfo;
/** Records commands only; this is not an ExoPlayer/AudioTrack implementation. */
public final class ExoPlayer {
    public AudioDeviceInfo preferred;
    public int requests;
    public boolean released;
    public void setPreferredAudioDevice(AudioDeviceInfo device) {
        if (released) throw new IllegalStateException();
        preferred = device; requests++;
    }
}
