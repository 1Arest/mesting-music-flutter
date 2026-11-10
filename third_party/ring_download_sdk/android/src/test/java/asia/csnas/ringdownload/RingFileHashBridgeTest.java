package asia.csnas.ringdownload;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public final class RingFileHashBridgeTest {
  private static int assertions;
  private static void check(boolean b) { assertions++; if(!b) throw new AssertionError(assertions); }
  private static String id(int n) { return String.format("%032x",n); }
  private static void dispatchOne(ArrayBlockingQueue<Runnable> queue) throws Exception {
    Runnable next=queue.poll(5,TimeUnit.SECONDS); check(next!=null); next.run();
  }
  private static void terminal(RingFileHashBridge bridge) {
    long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
    while(!bridge.terminated() && System.nanoTime()<deadline) Thread.yield();
    check(bridge.terminated()); check(bridge.activeCount()==0);
  }
  private static RingFileHashWorker.Opened empty(AtomicInteger closes) {
    return new RingFileHashWorker.Opened() {
      public InputStream input() { return new ByteArrayInputStream(new byte[0]); }
      public long size() { return 0; }
      public void verifyUnchanged() {}
      public void close() { closes.incrementAndGet(); }
    };
  }
  public static void main(String[] args) throws Exception {
    removedPendingReader(); removedQueuedReply(); removedError();
    System.out.println("{\"passed\":true,\"assertions\":"+assertions+",\"groups\":3}");
  }
  private static void removedPendingReader() throws Exception {
    CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
    AtomicInteger oldCloses=new AtomicInteger(),newCloses=new AtomicInteger();
    ArrayBlockingQueue<Runnable> oldMain=new ArrayBlockingQueue<>(8),newMain=new ArrayBlockingQueue<>(8);
    RingFileHashBridge old=new RingFileHashBridge(path -> {
      entered.countDown();
      if(!release.await(5,TimeUnit.SECONDS)) throw new IOException();
      return empty(oldCloses);
    },oldMain::add);
    CompletableFuture<RingFileHashWorker.Result> oldReply=new CompletableFuture<>(),nextReply=new CompletableFuture<>();
    old.hash(id(1),"old",oldReply::complete); check(entered.await(5,TimeUnit.SECONDS));
    old.close(); check(!oldReply.isDone()); check(oldCloses.get()==0);
    RingFileHashBridge next=new RingFileHashBridge(path -> empty(newCloses),newMain::add);
    next.hash(id(2),"next",nextReply::complete); dispatchOne(newMain);
    check("ok".equals(nextReply.get().code)); check(!oldReply.isDone());
    release.countDown(); dispatchOne(oldMain);
    check("unavailable".equals(oldReply.get().code)); check(oldCloses.get()==1);
    check(newCloses.get()==1); check(oldMain.isEmpty()); check(newMain.isEmpty());
    terminal(old); next.close(); terminal(next);
  }
  private static void removedQueuedReply() throws Exception {
    AtomicInteger closes=new AtomicInteger(); ArrayBlockingQueue<Runnable> main=new ArrayBlockingQueue<>(8);
    RingFileHashBridge bridge=new RingFileHashBridge(path -> empty(closes),main::add);
    CompletableFuture<RingFileHashWorker.Result> reply=new CompletableFuture<>();
    bridge.hash(id(1),"old",reply::complete);
    Runnable callback=main.poll(5,TimeUnit.SECONDS); check(callback!=null); check(closes.get()==1);
    bridge.close(); callback.run();
    check("unavailable".equals(reply.get().code)); terminal(bridge);
  }
  private static void removedError() throws Exception {
    ArrayBlockingQueue<Runnable> main=new ArrayBlockingQueue<>(8);
    RingFileHashBridge bridge=new RingFileHashBridge(path -> { throw new IOException(); },main::add);
    CompletableFuture<RingFileHashWorker.Result> reply=new CompletableFuture<>();
    bridge.hash(id(1),"error",reply::complete);
    Runnable callback=main.poll(5,TimeUnit.SECONDS); check(callback!=null);
    bridge.close(); callback.run(); check("error".equals(reply.get().code)); terminal(bridge);
  }
}
