package asia.csnas.ringdownload;

import java.util.function.Consumer;

/** One attachment owner. Dispatch and close are serialized on the main thread.
 * Each completion remains bound to its original channel reply, never the next
 * engine's channel. A removed plugin with a still-live Dart caller receives an
 * unavailable receipt only AFTER closure, rather than waiting forever. */
final class RingFileHashBridge {
  private final RingFileHashWorker worker;
  private final Consumer<Runnable> dispatch;
  private volatile boolean closed;
  RingFileHashBridge(RingFileHashWorker.Source source, Consumer<Runnable> dispatch) {
    this.worker = new RingFileHashWorker(source); this.dispatch = dispatch;
  }
  void hash(String id, String path, Consumer<RingFileHashWorker.Result> reply) {
    if (closed || !worker.submit(id, path, result -> dispatch.accept(() -> {
      // A close failure is never converted into permission to start fallback.
      reply.accept(closed && !"error".equals(result.code)
          ? RingFileHashWorker.Result.status("unavailable") : result);
    }))) reply.accept(RingFileHashWorker.Result.status("unavailable"));
  }
  boolean cancel(String id) { return worker.cancel(id); }
  void close() { closed = true; worker.close(); }
  int activeCount() { return worker.activeCount(); }
  boolean terminated() { return worker.terminated(); }
}
