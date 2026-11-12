package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor.StreamMetadata;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Copies small windows of the current player's PCM without changing its output.
 * The audio thread only captures samples. The channel reader analyzes the window
 * nearest to the position reported by the audio sink, which can lag queued PCM.
 */
public final class RhythmAudioProcessor extends BaseAudioProcessor {
    private static final int WINDOW = 2048;
    private static final int HISTORY = 64;
    private static final long MAX_DISTANCE_US = 120_000;
    private static final long MAX_POSITION_AGE_NS = 350_000_000;

    private final AtomicInteger generation = new AtomicInteger();
    private final float[] capture = new float[WINDOW];
    private volatile SampleWindow[] history;
    private volatile boolean enabled;
    private volatile long outputTimeUs = C.TIME_UNSET;
    private volatile long outputTimeAt;

    // Only the audio renderer updates this input cursor and the partial window.
    private long inputTimeUs = C.TIME_UNSET;
    private long inputFrames;
    private int captureGeneration = -1;
    private long sequence;
    private int points, strideFrames, countedSamples;
    private double mix, squares, peak;

    // Analysis is owned by the method-channel thread.
    private RhythmSpectrum spectrum;
    private float[] analysis;
    private long analyzedSequence;
    private Map<String, Object> analyzedFrame;

    private static final class SampleWindow {
        final float[] samples = new float[WINDOW];
        volatile long sequence;
        int generation;
        long timeUs;
        double sampleRate, rms, peak;
    }

    void setInputTimeUs(long timeUs) {
        if (inputTimeUs != timeUs) {
            inputTimeUs = timeUs;
            inputFrames = 0;
        }
    }

    void setOutputTimeUs(long timeUs) {
        if (!enabled) return;
        outputTimeUs = timeUs == Long.MIN_VALUE ? C.TIME_UNSET : timeUs;
        outputTimeAt = System.nanoTime();
    }

    public Map<String, Object> frame(boolean active) {
        if (!active) {
            if (enabled) {
                enabled = false;
                generation.incrementAndGet();
                analyzedFrame = null;
            }
            return Collections.singletonMap("available", false);
        }
        if (history == null) {
            SampleWindow[] windows = new SampleWindow[HISTORY];
            for (int i = 0; i < windows.length; i++) windows[i] = new SampleWindow();
            history = windows;
            spectrum = new RhythmSpectrum(WINDOW);
            analysis = new float[WINDOW];
        }
        enabled = true;
        long positionUs = outputTimeUs;
        long age = System.nanoTime() - outputTimeAt;
        if (positionUs == C.TIME_UNSET || age < 0 || age > MAX_POSITION_AGE_NS) {
            return Collections.singletonMap("available", false);
        }

        int currentGeneration = generation.get();
        SampleWindow nearest = null;
        long nearestSequence = 0;
        long distanceUs = MAX_DISTANCE_US;
        for (SampleWindow window : history) {
            long candidate = window.sequence;
            if (candidate == 0 || window.generation != currentGeneration) continue;
            long distance = Math.abs(window.timeUs - positionUs);
            if (distance < distanceUs) {
                nearest = window;
                nearestSequence = candidate;
                distanceUs = distance;
            }
        }
        if (nearest == null) return Collections.singletonMap("available", false);
        if (analyzedSequence == nearestSequence && analyzedFrame != null
                && currentGeneration == generation.get()) {
            return analyzedFrame;
        }
        System.arraycopy(nearest.samples, 0, analysis, 0, WINDOW);
        double rate = nearest.sampleRate;
        double rms = nearest.rms;
        double maximum = nearest.peak;
        // The producer invalidates the slot before overwriting it. Discard an
        // overlapped read instead of blocking the renderer or drawing a mixed frame.
        if (nearest.sequence != nearestSequence || currentGeneration != generation.get()) {
            return Collections.singletonMap("available", false);
        }
        Map<String, Object> result = new HashMap<>();
        result.put("available", true);
        result.put("rms", rms);
        result.put("peak", maximum);
        result.put("bands", spectrum.analyze(analysis, rate));
        result.put("frameId", nearestSequence);
        analyzedSequence = nearestSequence;
        analyzedFrame = result;
        return result;
    }

    @Override
    protected AudioFormat onConfigure(AudioFormat format) {
        return format.encoding == C.ENCODING_PCM_16BIT || format.encoding == C.ENCODING_PCM_FLOAT
            ? format : AudioFormat.NOT_SET;
    }

    @Override
    public void queueInput(ByteBuffer input) {
        if (!input.hasRemaining() || hasPendingOutput()) return;
        int epoch = generation.get();
        if (enabled && inputTimeUs != C.TIME_UNSET) {
            if (epoch != captureGeneration) {
                clearPartial();
                captureGeneration = epoch;
            }
            capture(input.duplicate().order(ByteOrder.LITTLE_ENDIAN), epoch);
        } else if (inputTimeUs != C.TIME_UNSET && inputAudioFormat.bytesPerFrame > 0) {
            // A lease can begin between retries of the same renderer buffer.
            inputFrames += input.remaining() / inputAudioFormat.bytesPerFrame;
        }
        replaceOutputBuffer(input.remaining()).put(input).flip();
    }

    private void capture(ByteBuffer input, int epoch) {
        boolean pcm16 = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT;
        int channels = inputAudioFormat.channelCount;
        int rate = inputAudioFormat.sampleRate;
        int stride = Math.max(1, (rate + 47_999) / 48_000);
        int width = pcm16 ? 2 : 4;
        int frameBytes = width * channels;
        for (int i = input.position(); i + frameBytes <= input.limit(); i += frameBytes) {
            double mono = 0;
            for (int channel = 0; channel < channels; channel++) {
                int offset = i + channel * width;
                double sample = pcm16 ? input.getShort(offset) / 32768.0 : input.getFloat(offset);
                sample = Double.isFinite(sample) ? Math.max(-1, Math.min(1, sample)) : 0;
                mono += sample;
                squares += sample * sample;
                peak = Math.max(peak, Math.abs(sample));
                countedSamples++;
            }
            inputFrames++;
            mix += mono / channels;
            if (++strideFrames < stride) continue;
            capture[points++] = (float) (mix / stride);
            mix = 0;
            strideFrames = 0;
            if (points == WINDOW) {
                long endUs = inputTimeUs + inputFrames * 1_000_000L / rate;
                long centreUs = endUs - (long) WINDOW * stride * 500_000L / rate;
                publish(epoch, centreUs, (double) rate / stride);
                clearPartial();
            }
        }
    }

    private void publish(int epoch, long timeUs, double rate) {
        SampleWindow window = history[(int) (sequence % HISTORY)];
        window.sequence = 0;
        System.arraycopy(capture, 0, window.samples, 0, WINDOW);
        window.generation = epoch;
        window.timeUs = timeUs;
        window.sampleRate = rate;
        window.rms = Math.sqrt(squares / countedSamples);
        window.peak = peak;
        window.sequence = ++sequence;
    }

    private void clearPartial() {
        points = strideFrames = countedSamples = 0;
        mix = squares = peak = 0;
    }

    @Override
    protected void onFlush(StreamMetadata metadata) {
        clearPartial();
        inputTimeUs = outputTimeUs = C.TIME_UNSET;
        inputFrames = 0;
        generation.incrementAndGet();
    }
}
