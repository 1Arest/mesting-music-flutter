package com.ryanheise.just_audio;

import android.media.AudioDeviceInfo;
import android.media.AudioRouting;
import android.media.AudioTrack;
import android.os.Handler;
import android.os.Looper;
import androidx.media3.exoplayer.ExoPlayer;
import java.util.concurrent.ConcurrentHashMap;

/** Per-owner access to Media3's actual track, without another player or hidden APIs.
 * Native requests, confirmed routes and paused preferences remain distinct. */
public final class MestingAudioOutput {
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final ConcurrentHashMap<String, Entry> OWNERS = new ConcurrentHashMap<>();

    private static final class Entry {
        volatile AudioTrack track;
        ExoPlayer player;
        volatile AudioDeviceInfo preferred;
        volatile Runnable observer;
        AudioRouting.OnRoutingChangedListener routeListener;
    }

    private static Entry entry(String owner) {
        return OWNERS.computeIfAbsent(owner, key -> new Entry());
    }

    private static void publish(Entry entry) {
        MAIN.post(() -> { if (entry.observer != null) entry.observer.run(); });
    }

    public static void observe(String owner, Runnable observer) { entry(owner).observer = observer; }
    public static void unobserve(String owner) { entry(owner).observer = null; }

    /** Main-thread binding. Tell Media3 about the preference as well as the
     * track so its sink/capabilities agree across format/source recreation. */
    public static void attachPlayer(String owner, ExoPlayer player) {
        Entry value = entry(owner);
        synchronized (value) {
            value.player = player;
            player.setPreferredAudioDevice(value.preferred);
        }
    }

    public static void releasePlayer(String owner, ExoPlayer player, AudioTrack track) {
        Entry value = entry(owner);
        synchronized (value) {
            // A stale disposal cannot unbind a newer lazy native instance.
            if (value.player == player) value.player = null;
        }
        releaseTrack(owner, track);
    }

    /** Called by the default AudioTrack provider on ExoPlayer's playback thread. */
    public static void observeTrack(String owner, AudioTrack track) {
        // Media3 validates failed AudioTracks after the provider returns. Do
        // not retain one or attach a routing callback before it is initialized.
        if (track.getState() != AudioTrack.STATE_INITIALIZED) return;
        Entry value = entry(owner);
        synchronized (value) {
            detach(value);
            value.track = track;
            value.routeListener = routing -> {
                if (value.track == routing) publish(value);
            };
            track.addOnRoutingChangedListener(value.routeListener, MAIN);
            if (value.preferred != null) track.setPreferredDevice(value.preferred);
        }
        publish(value);
    }

    private static void detach(Entry value) {
        if (value.track != null && value.routeListener != null) {
            try { value.track.removeOnRoutingChangedListener(value.routeListener); }
            catch (IllegalStateException ignored) { /* Already released by Media3. */ }
        }
        value.routeListener = null;
        value.track = null;
    }

    public static void releaseTrack(String owner, AudioTrack track) {
        Entry value = entry(owner);
        synchronized (value) {
            // A late old-player release must not detach a newly created track.
            if (track != null && value.track == track) detach(value);
        }
        publish(value);
    }

    public static AudioDeviceInfo currentDevice(String owner) {
        AudioTrack track = entry(owner).track;
        try { return track == null ? null : track.getRoutedDevice(); }
        catch (IllegalStateException ignored) { return null; }
    }

    public static AudioDeviceInfo preferredDevice(String owner) { return entry(owner).preferred; }

    public static boolean isPlaying(String owner) {
        AudioTrack track = entry(owner).track;
        try { return track != null && track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING; }
        catch (IllegalStateException ignored) { return false; }
    }

    /** False means Android rejected it. True is an accepted preference, which
     * does not become a confirmed route until getRoutedDevice/callback agrees. */
    public static boolean requestDevice(String owner, AudioDeviceInfo device) {
        Entry value = entry(owner);
        synchronized (value) {
            AudioDeviceInfo previous = value.preferred;
            try {
                if (value.track != null && value.track.getState() == AudioTrack.STATE_INITIALIZED
                        && !value.track.setPreferredDevice(device)) return false;
                if (value.player != null) value.player.setPreferredAudioDevice(device);
                value.preferred = device;
            } catch (IllegalStateException error) {
                // A lazy player can be released between the UI request and
                // the native call. Restore its track rather than leaving an
                // unreported preference behind after a failed request.
                if (value.track != null) {
                    try { value.track.setPreferredDevice(previous); }
                    catch (IllegalStateException ignored) { /* Already released. */ }
                }
                return false;
            }
        }
        publish(value);
        return true;
    }

    private MestingAudioOutput() {}
}
