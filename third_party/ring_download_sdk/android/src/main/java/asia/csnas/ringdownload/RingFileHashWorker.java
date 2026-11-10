package asia.csnas.ringdownload;

import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;
import java.util.function.LongSupplier;

/** Per Flutter engine: one reader, one waiter, no APK byte arrays across JNI.
 * IDs are unique per invocation in the Dart adapter. Cancel never releases a
 * running reader's ownership; its terminal callback follows try-with-resources.
 * The 30s budget is cooperative, not a hard bound on a kernel read/open call. */
final class RingFileHashWorker {
  static final long MAX_BYTES = 1024L * 1024 * 1024;
  interface Source { Opened open(String path) throws Exception; }
  interface Opened extends AutoCloseable {
    InputStream input();
    long size();
    void verifyUnchanged() throws Exception;
    @Override void close() throws IOException;
  }
  static final class Unavailable extends Exception {}
  static final class Result {
    final String code, sha256;
    final long bytes;
    Result(String code, String sha256, long bytes) {
      this.code = code; this.sha256 = sha256; this.bytes = bytes;
    }
    static Result status(String code) { return new Result(code, null, 0); }
  }
  private final Source source;
  private final LongSupplier clock;
  private final long budget;
  private final Map<String, Job> jobs = new HashMap<>();
  private final ThreadPoolExecutor executor;
  private boolean closed;

  RingFileHashWorker(Source source) { this(source, System::nanoTime, TimeUnit.SECONDS.toNanos(30)); }
  RingFileHashWorker(Source source, LongSupplier clock, long budget) {
    this.source = source; this.clock = clock; this.budget = budget;
    executor = new ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
        new ArrayBlockingQueue<>(1), task -> {
          Thread thread = new Thread(task, "ring-file-sha256");
          thread.setDaemon(true); return thread;
        });
  }

  boolean submit(String id, String path, Consumer<Result> completion) {
    synchronized (this) {
      if (closed || id == null || !id.matches("[a-f0-9]{32}") || path == null
          || path.length() > 4096 || jobs.containsKey(id) || jobs.size() >= 2) return false;
      Job job = new Job(id, path, completion);
      jobs.put(id, job);
      try { executor.execute(job); return true; }
      catch (RejectedExecutionException error) { jobs.remove(id); return false; }
    }
  }

  boolean cancel(String id) {
    Job job;
    boolean removed;
    synchronized (this) {
      job = jobs.get(id);
      if (job == null) return false;
      job.cancelled = true;
      removed = executor.remove(job);
    }
    if (removed) finish(job, Result.status("cancelled"));
    return true;
  }

  void close() {
    ArrayList<String> ids;
    synchronized (this) { closed = true; ids = new ArrayList<>(jobs.keySet()); }
    for (String id : ids) cancel(id);
    executor.shutdown();
  }
  synchronized int activeCount() { return jobs.size(); }
  boolean terminated() { return executor.isTerminated(); }

  private void finish(Job job, Result result) {
    synchronized (this) {
      if (jobs.get(job.id) != job) return;
      jobs.remove(job.id);
      if (job.cancelled && !"error".equals(result.code)) result = Result.status("cancelled");
    }
    job.completion.accept(result);
  }

  private final class Job implements Runnable {
    final String id, path;
    final Consumer<Result> completion;
    volatile boolean cancelled;
    Job(String id, String path, Consumer<Result> completion) {
      this.id = id; this.path = path; this.completion = completion;
    }
    private void check(long start) throws Exception {
      if (cancelled) throw new InterruptedException();
      if (clock.getAsLong() - start >= budget) throw new Unavailable();
    }
    @Override public void run() {
      Result result;
      long start = clock.getAsLong();
      try {
        check(start);
        // Every invocation opens and reads again. No path/mtime digest cache.
        try (Opened opened = source.open(path)) {
          long expected = opened.size(), count = 0;
          if (expected < 0 || expected > MAX_BYTES) throw new IOException();
          MessageDigest digest = MessageDigest.getInstance("SHA-256");
          byte[] buffer = new byte[65536];
          InputStream in = opened.input();
          for (;;) {
            check(start);
            int n = in.read(buffer);
            if (n == -1) break;
            count += n;
            if (count > expected) throw new IOException();
            digest.update(buffer, 0, n);
          }
          check(start);
          if (count != expected) throw new IOException();
          opened.verifyUnchanged();
          byte[] hash = digest.digest();
          StringBuilder hex = new StringBuilder(64);
          for (byte b : hash) {
            hex.append(Character.forDigit((b & 255) >>> 4, 16));
            hex.append(Character.forDigit(b & 15, 16));
          }
          result = new Result("ok", hex.toString(), count);
        }
      } catch (Unavailable error) {
        // A suppressed close error must not authorize a fallback reader.
        result = Result.status(error.getSuppressed().length == 0 ? "unavailable" : "error");
      } catch (InterruptedException error) {
        result = Result.status(error.getSuppressed().length == 0 ? "cancelled" : "error");
      }
      catch (Exception error) { result = Result.status("error"); }
      finish(this, result);
    }
  }
}
