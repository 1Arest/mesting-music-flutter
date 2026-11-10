package asia.csnas.ringdownload;

import android.content.Context;
import android.os.Build;
import android.os.Process;
import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import java.io.File;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;

/** API21+ file descriptors; no filesystem/network permissions are added. */
final class RingFileHashAndroid implements RingFileHashWorker.Source {
  private final Context context;
  private RingFileHashPathPolicy policy;
  RingFileHashAndroid(Context context) { this.context = context; }
  @Override public RingFileHashWorker.Opened open(String path) throws Exception {
    // Directory creation/canonicalization also runs on the single worker,
    // rather than adding disk work to Flutter engine attachment on the UI thread.
    if (policy == null) policy = new RingFileHashPathPolicy(new File[]{context.getFilesDir(),
        context.getCacheDir(), context.getNoBackupFilesDir()});
    File file = policy.resolve(path);
    FileDescriptor fd = Os.open(file.getPath(), OsConstants.O_RDONLY
        | OsConstants.O_CLOEXEC | OsConstants.O_NOFOLLOW | OsConstants.O_NONBLOCK, 0);
    try {
      StructStat initial = Os.fstat(fd);
      if (!OsConstants.S_ISREG(initial.st_mode) || initial.st_uid != Process.myUid()) {
        throw new IOException("invalid_file");
      }
      FileInputStream stream = new FileInputStream(fd);
      return new RingFileHashWorker.Opened() {
        @Override public InputStream input() { return stream; }
        @Override public long size() { return initial.st_size; }
        @Override public void verifyUnchanged() throws Exception {
          if (!same(initial, Os.fstat(fd)) || !same(initial, Os.stat(file.getPath()))) {
            throw new IOException("file_changed");
          }
        }
        @Override public void close() throws IOException {
          // Android FileInputStream(FileDescriptor) borrows this descriptor.
          // The code that opened it must explicitly close it before replying.
          try (FileInputStream borrowed = stream) {
            closeDescriptor(fd);
          }
        }
      };
    } catch (Exception error) {
      try { closeDescriptor(fd); }
      catch (IOException closeError) { error.addSuppressed(closeError); }
      throw error;
    }
  }
  private static void closeDescriptor(FileDescriptor fd) throws IOException {
    try { Os.close(fd); }
    catch (ErrnoException error) { throw new IOException("file_close_failed", error); }
  }
  private static boolean same(StructStat a, StructStat b) {
    if (a.st_dev != b.st_dev || a.st_ino != b.st_ino || a.st_size != b.st_size
        || a.st_mtime != b.st_mtime || a.st_ctime != b.st_ctime) return false;
    return Build.VERSION.SDK_INT < 27 || sameSubsecond(a, b);
  }
  @android.annotation.TargetApi(27)
  private static boolean sameSubsecond(StructStat a, StructStat b) {
    return a.st_mtim.tv_nsec == b.st_mtim.tv_nsec && a.st_ctim.tv_nsec == b.st_ctim.tv_nsec;
  }
}
