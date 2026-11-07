import android.media.AudioDeviceInfo;
import android.media.AudioTrack;
import android.os.Handler;
import androidx.media3.exoplayer.ExoPlayer;
import com.ryanheise.just_audio.MestingAudioOutput;

/** Executes the production routing registry against explicit host fakes.
 * Covers ownership/confirmation/lifecycle, never hardware or audio quality. */
public final class MestingAudioOutputHostTest {
    private static int checks;
    private static void check(boolean condition, String message) {
        checks++;
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        AudioDeviceInfo phone = new AudioDeviceInfo("phone"), buds = new AudioDeviceInfo("buds");
        String owner = "host-music", other = "host-chat";
        check(MestingAudioOutput.requestDevice(owner, phone), "Paused/no-track request accepted");
        check(MestingAudioOutput.currentDevice(owner) == null, "Preference is not a confirmed output");
        ExoPlayer first = new ExoPlayer();
        MestingAudioOutput.attachPlayer(owner, first);
        check(first.preferred == phone, "Lazy player inherits output preference");
        AudioTrack oldTrack = new AudioTrack();
        MestingAudioOutput.observeTrack(owner, oldTrack);
        check(oldTrack.preferred == phone, "New real track inherits preference");
        int[] notices = {0};
        MestingAudioOutput.observe(owner, () -> notices[0]++);
        oldTrack.confirm(phone); Handler.drain();
        check(MestingAudioOutput.currentDevice(owner) == phone, "Actual callback confirms output");
        check(notices[0] > 0, "Actual callback publishes route state");
        oldTrack.reject = true;
        check(!MestingAudioOutput.requestDevice(owner, buds), "Rejected request fails");
        check(MestingAudioOutput.preferredDevice(owner) == phone && first.preferred == phone,
            "Rejection preserves last choice in registry and player");
        oldTrack.reject = false;
        first.released = true;
        check(!MestingAudioOutput.requestDevice(owner, buds), "Released-player command fails");
        check(oldTrack.preferred == phone && MestingAudioOutput.preferredDevice(owner) == phone,
            "Released-player failure restores old track preference");
        ExoPlayer next = new ExoPlayer();
        MestingAudioOutput.attachPlayer(owner, next);
        AudioTrack nextTrack = new AudioTrack();
        MestingAudioOutput.observeTrack(owner, nextTrack);
        check(oldTrack.listeners == 0 && nextTrack.listeners == 1, "Track replacement moves callback");
        MestingAudioOutput.releasePlayer(owner, first, oldTrack);
        check(MestingAudioOutput.requestDevice(owner, buds), "Late old disposal leaves current player usable");
        check(next.preferred == buds && nextTrack.preferred == buds, "New choice reaches sink owner and current track");
        check(MestingAudioOutput.currentDevice(owner) == null, "New preference is pending until confirmed");
        nextTrack.confirm(buds);
        check(MestingAudioOutput.currentDevice(owner) == buds, "New track confirms actual output");
        check(MestingAudioOutput.preferredDevice(other) == null, "Music preference never leaks into another owner");
        nextTrack.playState = AudioTrack.PLAYSTATE_PLAYING;
        check(MestingAudioOutput.isPlaying(owner), "Active track state is read");
        nextTrack.released = true;
        check(!MestingAudioOutput.isPlaying(owner) && MestingAudioOutput.currentDevice(owner) == null,
            "Released-track reads are recoverable");
        nextTrack.released = false;
        check(MestingAudioOutput.requestDevice(owner, null), "Disconnected preference can return to system default");
        check(next.preferred == null && nextTrack.preferred == null, "Default clears player and track preferences");
        AudioTrack invalid = new AudioTrack(); invalid.state = 0;
        MestingAudioOutput.observeTrack(owner, invalid);
        check(invalid.listeners == 0 && nextTrack.listeners == 1, "Uninitialized track never replaces a valid route observer");
        MestingAudioOutput.releasePlayer(owner, next, nextTrack);
        check(nextTrack.listeners == 0, "Final release removes routing callback");
        Handler.drain();
        MestingAudioOutput.unobserve(owner);
        int before = notices[0];
        MestingAudioOutput.requestDevice(owner, phone); Handler.drain();
        check(notices[0] == before, "Disposed observer receives no later callbacks");
        System.out.println("PASS: " + checks + " native registry lifecycle assertions (host fakes; no device)");
    }
}
