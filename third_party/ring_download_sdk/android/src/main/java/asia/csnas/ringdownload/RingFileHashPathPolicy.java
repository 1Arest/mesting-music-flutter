package asia.csnas.ringdownload;

import java.io.File;
import java.io.IOException;

/** Canonical containment, including the separator: sibling-prefix is not inside. */
final class RingFileHashPathPolicy {
  private final String[] roots;
  RingFileHashPathPolicy(File[] directories) throws IOException {
    roots = new String[directories.length];
    for (int i=0; i<roots.length; i++) roots[i] = directories[i].getCanonicalPath() + File.separator;
  }
  File resolve(String path) throws IOException, RingFileHashWorker.Unavailable {
    File file = new File(path);
    if (!file.isAbsolute() || path.indexOf('\0') >= 0) throw new RingFileHashWorker.Unavailable();
    File canonical = file.getCanonicalFile();
    for (String root : roots) if (canonical.getPath().startsWith(root)) return canonical;
    throw new RingFileHashWorker.Unavailable();
  }
}
