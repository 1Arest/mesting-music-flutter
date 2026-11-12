package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/** Exercises the production processor against pinned Media3 buffer classes. */
public final class RhythmAudioProcessorHostTest {
    private static int passed;

    private static void check(boolean value, String name) {
        if (!value) throw new AssertionError(name);
        passed++;
        System.out.println("PASS " + name);
    }

    private static void queue(RhythmAudioProcessor processor, int rate, int encoding,
            long timeUs, double amplitude, double frequency) {
        int stride = Math.max(1, (rate + 47_999) / 48_000);
        int frames = 2048 * stride;
        ByteBuffer input = ByteBuffer.allocateDirect(frames * (encoding == C.ENCODING_PCM_16BIT ? 4 : 8))
            .order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < frames; i++) {
            double sample = amplitude * Math.sin(2 * Math.PI * frequency * i / rate);
            for (int channel = 0; channel < 2; channel++) {
                if (encoding == C.ENCODING_PCM_16BIT) {
                    input.putShort((short) (sample * 32767));
                } else {
                    input.putFloat((float) sample);
                }
            }
        }
        input.flip();
        byte[] expected = new byte[input.remaining()];
        input.duplicate().get(expected);
        processor.setInputTimeUs(timeUs);
        processor.queueInput(input);
        processor.queueInput(AudioProcessor.EMPTY_BUFFER);
        ByteBuffer output = processor.getOutput();
        byte[] actual = new byte[output.remaining()];
        output.get(actual);
        check(Arrays.equals(expected, actual), "preserved PCM " + rate + "/" + frequency);
    }

    private static double value(Map<String, Object> frame, String key) {
        return ((Number) frame.get(key)).doubleValue();
    }

    private static int dominantBand(Map<String, Object> frame) {
        List<?> bands = (List<?>) frame.get("bands");
        int best = 0;
        for (int i = 1; i < bands.size(); i++) {
            if (((Number) bands.get(i)).doubleValue() > ((Number) bands.get(best)).doubleValue()) best = i;
        }
        return best;
    }

    public static void main(String[] args) throws Exception {
        for (int encoding : new int[] { C.ENCODING_PCM_16BIT, C.ENCODING_PCM_FLOAT }) {
            int rate = encoding == C.ENCODING_PCM_FLOAT ? 96_000 : 48_000;
            RhythmAudioProcessor processor = new RhythmAudioProcessor();
            processor.queueInput(AudioProcessor.EMPTY_BUFFER);
            check(!processor.getOutput().hasRemaining(), "empty before configuration " + encoding);
            processor.configure(new AudioProcessor.AudioFormat(rate, 2, encoding));
            processor.flush();
            processor.frame(true);
            queue(processor, rate, encoding, 0, .11, 84);
            queue(processor, rate, encoding, 350_000, .76, 1940);
            queue(processor, rate, encoding, 750_000, 0, 84);
            processor.setOutputTimeUs(22_000);
            Map<String, Object> quiet = processor.frame(true);
            check(Math.abs(value(quiet, "rms") - .11 / Math.sqrt(2)) < .005,
                "queued loud PCM does not replace the audible quiet window");
            check(dominantBand(quiet) <= 2, "bass tone reaches the low bands");
            processor.setOutputTimeUs(372_000);
            Map<String, Object> loud = processor.frame(true);
            check(value(loud, "rms") > value(quiet, "rms") * 6, "RMS follows the actual loud passage");
            check(dominantBand(loud) >= 7, "mid/high tone reaches different bands");
            check(value(loud, "frameId") != value(quiet, "frameId"), "separate measured windows");
            processor.setOutputTimeUs(772_000);
            Map<String, Object> silent = processor.frame(true);
            check(value(silent, "rms") == 0 && value(silent, "peak") == 0,
                "digital silence produces no activity");
            processor.setOutputTimeUs(1_300_000);
            check(processor.frame(true).get("available").equals(false), "out-of-range clock has no fake frame");
            check(processor.frame(false).get("available").equals(false), "disabled meter has no frame");
            processor.setOutputTimeUs(22_000);
            check(processor.frame(true).get("available").equals(false), "reenabling cannot reuse previous windows");
            processor.flush();
            check(processor.frame(true).get("available").equals(false), "seek flush invalidates the timeline");
            processor.reset();
        }
        System.out.println("Rhythm host checks passed: " + passed);
    }
}
