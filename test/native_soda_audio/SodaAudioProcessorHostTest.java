import android.content.Context;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import com.ryanheise.just_audio.SodaAudioProcessor;
import com.luna.audio.effect.AudioEffectBridge;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.io.ByteArrayOutputStream;
import java.util.Arrays;

/** Exercises production Java with the actual pinned Media3 buffer classes. */
public final class SodaAudioProcessorHostTest {
    private static int passed;
    private interface Case { void run() throws Exception; }
    private static void test(String name, Case c) throws Exception {
        c.run(); passed++; System.out.println("PASS " + name);
    }
    private static SodaAudioProcessor processor(int encoding) throws Exception {
        SodaAudioProcessor p = new SodaAudioProcessor(new Context());
        p.configure(new AudioProcessor.AudioFormat(48000, 2, encoding)); p.flush(); return p;
    }
    private static byte[] bytes(int count) {
        byte[] a = new byte[count]; for (int i = 0; i < count; i++) a[i] = (byte)(i * 31 + 7); return a;
    }
    private static ByteBuffer input(byte[] a) {
        ByteBuffer b = ByteBuffer.allocateDirect(a.length).order(ByteOrder.LITTLE_ENDIAN);
        b.put(a).flip(); return b;
    }
    private static byte[] output(SodaAudioProcessor p) {
        ByteBuffer b = p.getOutput(); byte[] a = new byte[b.remaining()]; b.get(a); return a;
    }
    private static void equal(byte[] a, byte[] b) {
        if (!Arrays.equals(a,b)) throw new AssertionError("PCM differs: expected=" + a.length + ", actual=" + b.length);
    }
    private static void empty(SodaAudioProcessor p) { p.queueInput(AudioProcessor.EMPTY_BUFFER); }
    public static void main(String[] args) throws Exception {
        test("first shared EMPTY_BUFFER never self-copies", () -> {
            SodaAudioProcessor p = processor(C.ENCODING_PCM_16BIT); empty(p); equal(new byte[0],output(p));
        });
        test("empty input before configure is harmless", () -> empty(new SodaAudioProcessor(new Context())));
        test("empty input preserves unread output", () -> {
            SodaAudioProcessor p = processor(C.ENCODING_PCM_16BIT); byte[] a = bytes(120);
            p.queueInput(input(a)); empty(p); equal(a,output(p));
        });
        for (int encoding : new int[]{C.ENCODING_PCM_16BIT,C.ENCODING_PCM_FLOAT}) {
            for (int size : new int[]{4,2048,8192}) {
                test("exact ordinary bypass encoding="+encoding+" bytes="+size, () -> {
                    SodaAudioProcessor p = processor(encoding); byte[] a=bytes(size);
                    p.queueInput(input(a)); equal(a,output(p)); empty(p); equal(new byte[0],output(p));
                });
            }
        }
        test("flush and reset accept the shared empty sentinel repeatedly", () -> {
            SodaAudioProcessor p=processor(C.ENCODING_PCM_16BIT);
            for(int i=0;i<12;i++){p.flush();empty(p);equal(new byte[0],output(p));p.reset();empty(p);
                p.configure(new AudioProcessor.AudioFormat(44100,2,C.ENCODING_PCM_16BIT));p.flush();}
        });
        test("failed native creation preserves every fragmented PCM16 byte at EOS", () -> {
            AudioEffectBridge.failCreate=true;
            try {
                SodaAudioProcessor p=processor(C.ENCODING_PCM_16BIT);p.select("{}");
                byte[] a=bytes(4348); ByteArrayOutputStream all=new ByteArrayOutputStream();
                for(int offset=0;offset<a.length;offset+=316){
                    p.queueInput(input(Arrays.copyOfRange(a,offset,Math.min(a.length,offset+316))));
                    all.write(output(p));empty(p);
                }
                p.queueEndOfStream();all.write(output(p));equal(a,all.toByteArray());
                if(!p.isEnded())throw new AssertionError("EOS not drained");
            } finally { AudioEffectBridge.failCreate=false; }
        });
        test("disabling effect drains an already buffered partial block", () -> {
            SodaAudioProcessor p=processor(C.ENCODING_PCM_16BIT);p.select("{}");
            byte[] a=bytes(76),b=bytes(2048);ByteArrayOutputStream all=new ByteArrayOutputStream();
            p.queueInput(input(a));all.write(output(p));p.select(null);empty(p);
            p.queueInput(input(b));all.write(output(p));p.queueEndOfStream();all.write(output(p));
            ByteArrayOutputStream expected=new ByteArrayOutputStream();expected.write(a);expected.write(b);
            equal(expected.toByteArray(),all.toByteArray());
        });
        test("float effect tail has no extra padded frames", () -> {
            SodaAudioProcessor p=processor(C.ENCODING_PCM_FLOAT);p.select("{}");
            ByteBuffer b=ByteBuffer.allocateDirect(19*8).order(ByteOrder.LITTLE_ENDIAN);
            for(int i=0;i<38;i++)b.putFloat((i-19)/40f);b.flip();
            byte[] expected=new byte[b.remaining()];b.duplicate().get(expected);
            p.queueInput(b);equal(new byte[0],output(p));empty(p);p.queueEndOfStream();equal(expected,output(p));
        });
        test("empty EOS completes without creating an output buffer", () -> {
            SodaAudioProcessor p=processor(C.ENCODING_PCM_16BIT);empty(p);p.queueEndOfStream();
            equal(new byte[0],output(p));if(!p.isEnded())throw new AssertionError("empty EOS stuck");
        });
        System.out.println("Soda audio host regression: " + passed + " passed; actual Media3 1.9.2 classes, native bridge simulated.");
    }
}
