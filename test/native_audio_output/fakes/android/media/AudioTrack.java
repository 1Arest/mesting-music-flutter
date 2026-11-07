package android.media;
import android.os.Handler;
/** Controllable public-API fake. Requested and actual routes are independent. */
public final class AudioTrack implements AudioRouting {
    public static final int STATE_INITIALIZED = 1, PLAYSTATE_PLAYING = 3;
    public int state = STATE_INITIALIZED, playState;
    public AudioDeviceInfo preferred, actual;
    public boolean reject, released;
    public int listeners;
    private OnRoutingChangedListener listener;
    public int getState() { return state; }
    public int getPlayState() { if (released) throw new IllegalStateException(); return playState; }
    public AudioDeviceInfo getRoutedDevice() { if (released) throw new IllegalStateException(); return actual; }
    public boolean setPreferredDevice(AudioDeviceInfo device) {
        if (released) throw new IllegalStateException();
        if (reject) return false;
        preferred = device; return true;
    }
    public void addOnRoutingChangedListener(OnRoutingChangedListener value, Handler handler) { listener = value; listeners++; }
    public void removeOnRoutingChangedListener(OnRoutingChangedListener value) { if (listener == value) { listener = null; listeners--; } }
    public void confirm(AudioDeviceInfo device) { actual = device; if (listener != null) listener.onRoutingChanged(this); }
}
