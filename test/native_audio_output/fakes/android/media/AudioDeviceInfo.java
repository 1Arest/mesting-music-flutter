package android.media;
/** Identity-only host fake; it makes no claim about Android route availability. */
public final class AudioDeviceInfo {
    public final String id;
    public AudioDeviceInfo(String id) { this.id = id; }
}
