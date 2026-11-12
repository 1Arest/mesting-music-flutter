package com.ryanheise.just_audio;

import android.content.Context;
import android.content.SharedPreferences;
import androidx.media3.common.C;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

/** Audio-thread PCM accounting, before optional effects. Control-thread requests
 * are immutable. A new source/seek invalidates unfinished measurements; only a
 * complete, unseeked recording can populate the bounded local cache. */
public final class MusicLoudnessProcessor extends BaseAudioProcessor {
    private final SharedPreferences cache;
    private volatile Config requested = new Config("", false, 0, 1, 0);
    private Config current;
    private TrackLoudnessMeter meter;
    private long appliedGeneration = -1;
    private volatile long invalidGeneration = -1;
    private static final class Config {
        final String key; final boolean enabled; final long duration, generation; final double gain;
        Config(String key,boolean enabled,long duration,double gain,long generation) {
            this.key=key;this.enabled=enabled;this.duration=duration;this.gain=gain;this.generation=generation;
        }
    }
    public MusicLoudnessProcessor(Context context) { cache=context.getSharedPreferences("music_loudness_v1", Context.MODE_PRIVATE); }
    public void select(String identity,boolean enabled,long duration,boolean invalidate) {
        if (invalidate) { invalidGeneration=requested.generation; return; }
        String key = digest(identity == null ? "" : identity);
        double gain=1;
        try { gain=Double.parseDouble(cache.getString(key,"1")); } catch (RuntimeException ignored) { }
        if (!Double.isFinite(gain) || gain <= 0 || gain > 4) gain=1;
        requested=new Config(key,enabled,duration,gain,requested.generation+1);
    }
    private static String digest(String s) {
        try { byte[] b=MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
            StringBuilder out=new StringBuilder();for(byte v:b)out.append(String.format("%02x",v&255));return out.toString();
        } catch (Exception e) { return ""; }
    }
    @Override protected AudioFormat onConfigure(AudioFormat format) {
        return format.channelCount >= 1 && format.channelCount <= 2 &&
            (format.encoding == C.ENCODING_PCM_16BIT || format.encoding == C.ENCODING_PCM_FLOAT) ? format : AudioFormat.NOT_SET;
    }
    @Override public void queueInput(ByteBuffer input) {
        if (!input.hasRemaining() || hasPendingOutput()) return;
        Config c=requested;
        if (appliedGeneration != c.generation) { current=c;appliedGeneration=c.generation;meter=null; }
        ByteBuffer output=replaceOutputBuffer(input.remaining()).order(ByteOrder.LITTLE_ENDIAN);
        if (!c.enabled) { output.put(input).flip(); return; }
        if (meter==null) meter=new TrackLoudnessMeter(inputAudioFormat.sampleRate,inputAudioFormat.channelCount);
        input.order(ByteOrder.LITTLE_ENDIAN);
        boolean pcm16=inputAudioFormat.encoding==C.ENCODING_PCM_16BIT;
        int channel=0;
        while (input.remaining() >= (pcm16 ? 2 : 4)) {
            double value=pcm16 ? input.getShort()/32768.0 : input.getFloat();
            meter.sample(value,channel);channel=(channel+1)%inputAudioFormat.channelCount;
            value=Double.isFinite(value) ? Math.max(-1,Math.min(1,value*c.gain)) : 0;
            if (pcm16) output.putShort((short)Math.round(value < 0 ? value*32768 : value*32767)); else output.putFloat((float)value);
        }
        output.flip();
    }
    @Override protected void onQueueEndOfStream() {
        Config c=current;
        if(c==null || meter==null || c.generation==invalidGeneration || c.generation!=requested.generation) return;
        Double gain=meter.gain(c.duration);
        if(gain!=null && !c.key.isEmpty()) {
            // Eviction bounds metadata only; audio and personal listening data
            // are not retained. Android applies disk writes asynchronously.
            if(cache.getAll().size() >= 1000 && !cache.contains(c.key)) cache.edit().clear().apply();
            cache.edit().putString(c.key,Double.toString(gain)).apply();
        }
    }
    @Override @SuppressWarnings("deprecation") protected void onFlush() { meter=null; }
    @Override protected void onReset() { meter=null;current=null;appliedGeneration=-1; }
}
