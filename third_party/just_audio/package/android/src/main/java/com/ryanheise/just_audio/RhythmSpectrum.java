package com.ryanheise.just_audio;

import java.util.ArrayList;
import java.util.List;

/** Converts one window of mono PCM into a small set of logarithmic bands. */
final class RhythmSpectrum {
    private static final double[] EDGES = {30, 65, 100, 160, 250, 400, 630,
        1000, 1600, 2500, 4000, 6500, 12000};
    private final int size;
    private final int[] reverse;
    private final double[] real, imaginary, window, cosine, sine;

    RhythmSpectrum(int size) {
        this.size = size;
        reverse = new int[size];
        real = new double[size];
        imaginary = new double[size];
        window = new double[size];
        cosine = new double[size / 2];
        sine = new double[size / 2];
        int shift = 32 - Integer.numberOfTrailingZeros(size);
        for (int i = 0; i < size; i++) {
            reverse[i] = Integer.reverse(i) >>> shift;
            window[i] = .5 - .5 * Math.cos(2 * Math.PI * i / (size - 1));
        }
        for (int i = 0; i < size / 2; i++) {
            double angle = -2 * Math.PI * i / size;
            cosine[i] = Math.cos(angle);
            sine[i] = Math.sin(angle);
        }
    }

    List<Double> analyze(float[] samples, double rate) {
        for (int i = 0; i < size; i++) {
            real[reverse[i]] = samples[i] * window[i];
            imaginary[reverse[i]] = 0;
        }
        for (int span = 2; span <= size; span *= 2) {
            int half = span / 2;
            int step = size / span;
            for (int start = 0; start < size; start += span) {
                for (int j = 0; j < half; j++) {
                    int left = start + j;
                    int right = left + half;
                    int rotation = j * step;
                    double r = real[right] * cosine[rotation] - imaginary[right] * sine[rotation];
                    double i = real[right] * sine[rotation] + imaginary[right] * cosine[rotation];
                    real[right] = real[left] - r;
                    imaginary[right] = imaginary[left] - i;
                    real[left] += r;
                    imaginary[left] += i;
                }
            }
        }
        List<Double> bands = new ArrayList<>(EDGES.length - 1);
        for (int band = 0; band < EDGES.length - 1; band++) {
            int first = Math.max(1, (int) Math.ceil(EDGES[band] * size / rate));
            int end = Math.min(size / 2, (int) Math.ceil(EDGES[band + 1] * size / rate));
            double power = 0;
            for (int bin = first; bin < end; bin++) {
                power = Math.max(power, real[bin] * real[bin] + imaginary[bin] * imaginary[bin]);
            }
            bands.add(Math.min(1, Math.sqrt(power) * 4 / size));
        }
        return bands;
    }
}
