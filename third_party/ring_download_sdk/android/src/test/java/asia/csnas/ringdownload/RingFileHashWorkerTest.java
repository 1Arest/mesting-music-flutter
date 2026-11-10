package asia.csnas.ringdownload;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/** JVM qualification of the real worker, no Android/Flutter fake event loop. */
public final class RingFileHashWorkerTest {
  private static int assertions;
  private static void check(boolean value) {
    assertions++; if (!value) throw new AssertionError("assertion " + assertions);
  }
  private static String id(int value) { return String.format("%032x", value); }
  private static RingFileHashWorker.Result get(CompletableFuture<RingFileHashWorker.Result> f) throws Exception {
    return f.get(5, TimeUnit.SECONDS);
  }
  private static CompletableFuture<RingFileHashWorker.Result> start(RingFileHashWorker w, int id, String path) {
    CompletableFuture<RingFileHashWorker.Result> f = new CompletableFuture<>();
    check(w.submit(id(id), path, f::complete)); return f;
  }
  private static RingFileHashWorker.Opened opened(InputStream in, long size, AtomicInteger closes) {
    return new RingFileHashWorker.Opened() {
      public InputStream input() { return in; }
      public long size() { return size; }
      public void verifyUnchanged() throws Exception {}
      public void close() throws IOException { closes.incrementAndGet(); in.close(); }
    };
  }
  private static void stop(RingFileHashWorker w) throws Exception {
    w.close();
    long end = System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
    while (!w.terminated() && System.nanoTime()<end) Thread.yield();
    check(w.terminated()); check(w.activeCount()==0);
  }
  private static String sha(byte[] bytes) throws Exception {
    StringBuilder out = new StringBuilder();
    for(byte b:MessageDigest.getInstance("SHA-256").digest(bytes)) out.append(String.format("%02x", b&255));
    return out.toString();
  }
  public static void main(String[] args) throws Exception {
    File dir = Files.createTempDirectory("ring-hash-worker-").toFile();
    try {
      freshAndMissing(dir); limitsAndClose(); cancelAndCapacity(); detach(); budget(); failures(); paths(dir); budgetCloseFailure();
    } finally {
      File[] files=dir.listFiles(); if(files!=null) for(File f:files) Files.delete(f.toPath());
      Files.delete(dir.toPath());
    }
    System.out.println("{\"passed\":true,\"assertions\":"+assertions+",\"groups\":8}");
  }
  private static void freshAndMissing(File dir) throws Exception {
    AtomicInteger closes=new AtomicInteger();
    RingFileHashWorker w=new RingFileHashWorker(path -> {
      File f=new File(path); return opened(new FileInputStream(f),f.length(),closes);
    });
    File file=new File(dir,"fixture.bin");
    byte[] first=new byte[65537]; for(int i=0;i<first.length;i++) first[i]=(byte)i;
    Files.write(file.toPath(),first);
    RingFileHashWorker.Result a=get(start(w,1,file.getPath()));
    check("ok".equals(a.code)); check(a.sha256.equals(sha(first))); check(a.bytes==first.length); check(closes.get()==1);
    first[0]=37; Files.write(file.toPath(),first);
    RingFileHashWorker.Result b=get(start(w,2,file.getPath()));
    check(!a.sha256.equals(b.sha256)); check(b.sha256.equals(sha(first))); check(closes.get()==2);
    Files.write(file.toPath(),new byte[0]);
    check(get(start(w,3,file.getPath())).sha256.equals(sha(new byte[0])));
    Files.delete(file.toPath()); check("error".equals(get(start(w,4,file.getPath())).code));
    stop(w);
  }
  private static void limitsAndClose() throws Exception {
    for(long declared:new long[]{RingFileHashWorker.MAX_BYTES+1,10,1}) {
      AtomicInteger closes=new AtomicInteger();
      RingFileHashWorker w=new RingFileHashWorker(path -> opened(new ByteArrayInputStream(new byte[]{1,2,3}),declared,closes));
      check("error".equals(get(start(w,1,"/fixture")).code)); check(closes.get()==1); stop(w);
    }
  }
  private static void cancelAndCapacity() throws Exception {
    CountDownLatch reading=new CountDownLatch(1), release=new CountDownLatch(1);
    AtomicInteger opens=new AtomicInteger(), closes=new AtomicInteger();
    RingFileHashWorker w=new RingFileHashWorker(path -> {
      opens.incrementAndGet();
      InputStream in=new InputStream() {
        public int read() { return -1; }
        public int read(byte[] buffer) throws IOException {
          if(path.equals("held")) {
            reading.countDown();
            try { if(!release.await(5,TimeUnit.SECONDS)) throw new IOException(); }
            catch(InterruptedException e) { throw new IOException(e); }
          }
          return -1;
        }
      };
      return opened(in,0,closes);
    });
    CompletableFuture<RingFileHashWorker.Result> first=start(w,1,"held");
    check(reading.await(5,TimeUnit.SECONDS));
    CompletableFuture<RingFileHashWorker.Result> queued=start(w,2,"queued");
    check(w.activeCount()==2);
    check(!w.submit(id(3),"extra",r -> {})); check(!w.submit(id(1),"duplicate",r -> {}));
    check(!w.submit("bad","invalid",r -> {}));
    check(w.cancel(id(2))); check("cancelled".equals(get(queued).code)); check(opens.get()==1);
    check(w.cancel(id(1))); check(!first.isDone()); check(closes.get()==0);
    CompletableFuture<RingFileHashWorker.Result> next=start(w,4,"next");
    release.countDown(); check("cancelled".equals(get(first).code));
    check(!w.cancel(id(1))); check("ok".equals(get(next).code)); check(closes.get()==2); stop(w);
  }
  private static void detach() throws Exception {
    CountDownLatch opened=new CountDownLatch(1),release=new CountDownLatch(1);
    AtomicInteger closes=new AtomicInteger();
    RingFileHashWorker w=new RingFileHashWorker(path -> {
      opened.countDown();
      try { if(!release.await(5,TimeUnit.SECONDS)) throw new IOException(); }
      catch(InterruptedException e) { throw new IOException(e); }
      return opened(new ByteArrayInputStream(new byte[0]),0,closes);
    });
    CompletableFuture<RingFileHashWorker.Result> one=start(w,1,"held"); check(opened.await(5,TimeUnit.SECONDS));
    CompletableFuture<RingFileHashWorker.Result> two=start(w,2,"queued");
    w.close(); check("cancelled".equals(get(two).code)); check(!one.isDone());
    check(!w.submit(id(3),"late",r -> {})); release.countDown();
    check("cancelled".equals(get(one).code)); check(closes.get()==1); stop(w);
  }
  private static void budget() throws Exception {
    AtomicLong clock=new AtomicLong(); AtomicInteger closes=new AtomicInteger();
    RingFileHashWorker w=new RingFileHashWorker(path -> opened(new InputStream() {
      public int read() { return -1; }
      public int read(byte[] bytes) { clock.set(30); return -1; }
    },0,closes),clock::get,30);
    check("unavailable".equals(get(start(w,1,"fixture")).code)); check(closes.get()==1); stop(w);
  }
  private static void failures() throws Exception {
    for(boolean failClose:new boolean[]{false,true}) {
      AtomicBoolean closed=new AtomicBoolean();
      RingFileHashWorker w=new RingFileHashWorker(path -> new RingFileHashWorker.Opened() {
        public InputStream input() { return new ByteArrayInputStream(new byte[0]); }
        public long size() { return 0; }
        public void verifyUnchanged() throws IOException { if(!failClose) throw new IOException(); }
        public void close() throws IOException { closed.set(true); if(failClose) throw new IOException(); }
      });
      check("error".equals(get(start(w,1,"fixture")).code)); check(closed.get()); stop(w);
    }
  }
  private static void paths(File dir) throws Exception {
    File root=new File(dir,"inside"); check(root.mkdir());
    RingFileHashPathPolicy policy=new RingFileHashPathPolicy(new File[]{root});
    check(policy.resolve(new File(root,"a").getPath()).getCanonicalFile().equals(new File(root,"a").getCanonicalFile()));
    for(String path:new String[]{new File(dir,"inside-other/a").getPath(),"relative/a",new File(root,"../outside").getPath()}) {
      boolean rejected=false; try { policy.resolve(path); } catch(RingFileHashWorker.Unavailable expected) { rejected=true; }
      check(rejected);
    }
    Files.delete(root.toPath());
  }
  private static void budgetCloseFailure() throws Exception {
    AtomicLong clock=new AtomicLong(); AtomicBoolean closed=new AtomicBoolean();
    RingFileHashWorker w=new RingFileHashWorker(path -> new RingFileHashWorker.Opened() {
      public InputStream input() { return new InputStream() {
        public int read() { return -1; }
        public int read(byte[] buffer) { clock.set(30); return -1; }
      }; }
      public long size() { return 0; }
      public void verifyUnchanged() {}
      public void close() throws IOException { closed.set(true); throw new IOException("close failed"); }
    },clock::get,30);
    check("error".equals(get(start(w,1,"fixture")).code)); check(closed.get()); stop(w);
  }
}
