package com.ryanheise.just_audio;

import java.util.ArrayList;

/** Bounded BS.1770-style mono/stereo K-weighted integrated measurement.
 * 400ms windows at 100ms intervals use absolute -70 LUFS and relative -10 LU
 * gates. Silence cannot determine a boost. This is a fixed per-recording gain,
 * not a compressor: samples within a song retain their original relationships.
 * The peak bound includes 2dB headroom; no true-peak certification is claimed.
 * Pure Java deliberately keeps numeric tests independent of Android/decoders. */
public final class TrackLoudnessMeter {
    private final int rate, channels, hop;
    private final Filter[] shelf, highpass;
    private final double[] ring = new double[4];
    private final ArrayList<Double> windows = new ArrayList<>();
    private int chunkFrames, chunks;
    private long frames;
    private double energy, peak;
    private boolean invalid;
    public TrackLoudnessMeter(int rate, int channels) {
        this.rate = rate; this.channels = channels; hop = Math.max(1, rate / 10);
        shelf = new Filter[channels]; highpass = new Filter[channels];
        for (int c = 0; c < channels; c++) {
            double k = Math.tan(Math.PI * 1681.974450955533 / rate);
            double q = .7071752369554196, vh = Math.pow(10, 3.999843853973347 / 20), vb = Math.pow(vh, .4996667741545416);
            double a = 1 + k/q + k*k;
            shelf[c] = new Filter((vh + vb*k/q + k*k)/a, 2*(k*k-vh)/a, (vh-vb*k/q+k*k)/a, 2*(k*k-1)/a, (1-k/q+k*k)/a);
            k = Math.tan(Math.PI * 38.13547087602444 / rate); q = .5003270373238773; a = 1 + k/q + k*k;
            highpass[c] = new Filter(1, -2, 1, 2*(k*k-1)/a, (1-k/q+k*k)/a);
        }
    }
    public void sample(double value, int channel) {
        if (!Double.isFinite(value)) { invalid = true; value = 0; }
        peak = Math.max(peak, Math.abs(value));
        double weighted = highpass[channel].apply(shelf[channel].apply(value));
        energy += weighted * weighted;
        if (channel == channels - 1) {
            frames++;
            if (++chunkFrames >= hop) {
                ring[chunks % 4] = energy / chunkFrames; energy = 0; chunkFrames = 0; chunks++;
                if (chunks >= 4) {
                    if (windows.size() >= 216000) { invalid = true; return; } // six hours
                    windows.add((ring[0]+ring[1]+ring[2]+ring[3])/4);
                }
            }
        }
    }
    public long frames() { return frames; }
    public Double gain(long expectedMilliseconds) {
        if (invalid || expectedMilliseconds < 10000 || frames < rate * 10L ||
            frames < expectedMilliseconds * rate / 1000.0 * .98 ||
            frames > expectedMilliseconds * rate / 1000.0 * 1.02 || peak <= 0) return null;
        double sum = 0; int count = 0;
        for (double e : windows) if (lufs(e) > -70) { sum += e; count++; }
        if (count == 0) return null;
        double gate = Math.max(-70, lufs(sum/count) - 10); sum = 0; count = 0;
        for (double e : windows) if (lufs(e) > gate) { sum += e; count++; }
        if (count == 0) return null;
        double db = Math.min(12, Math.max(-12, -16 - lufs(sum/count)));
        // Never clip a large transient to make a quiet recording louder.
        return Math.min(Math.pow(10, db/20), Math.pow(10, -2.0/20)/peak);
    }
    private static double lufs(double energy) { return -.691 + 10*Math.log10(Math.max(1e-30, energy)); }
    private static final class Filter {
        final double b0,b1,b2,a1,a2; double z1,z2;
        Filter(double b0,double b1,double b2,double a1,double a2) { this.b0=b0;this.b1=b1;this.b2=b2;this.a1=a1;this.a2=a2; }
        double apply(double x) { double y=b0*x+z1;z1=b1*x-a1*y+z2;z2=b2*x-a2*y;return y; }
    }
}
