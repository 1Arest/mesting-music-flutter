import com.ryanheise.just_audio.TrackLoudnessMeter;
public class TrackLoudnessMeterTest {
  static TrackLoudnessMeter tone(double amplitude, boolean silence, int rate) {
    TrackLoudnessMeter m = new TrackLoudnessMeter(rate, 2);
    for(int f=0;f<rate*12;f++) {
      double sample=silence?0:amplitude*Math.sin(2*Math.PI*1000*f/rate);
      m.sample(sample,0);m.sample(sample,1);
    }
    return m;
  }
  public static void main(String[] args) {
    for (int rate : new int[]{44100,48000,96000}) {
      Double quiet=tone(.05,false,rate).gain(12000), loud=tone(.5,false,rate).gain(12000);
      if(quiet==null||loud==null)throw new AssertionError("missing measurement");
      if(Math.abs(20*Math.log10(quiet/loud)-20)>.2)throw new AssertionError("normalization target differs by input level");
      if(tone(.5,true,rate).gain(12000)!=null)throw new AssertionError("silence amplified");
      if(tone(.5,false,rate).gain(30000)!=null)throw new AssertionError("partial track accepted");
      System.out.println("rate="+rate+" measured fixed gains quiet="+quiet+" loud="+loud);
    }
    TrackLoudnessMeter transientTrack=tone(.005,false,48000);
    transientTrack.sample(1,0);transientTrack.sample(1,1);
    if(transientTrack.gain(12000)>Math.pow(10,-2.0/20)+.000001)throw new AssertionError("peak headroom lost");
    System.out.println("PASS: 3 rates, level matching, silence, coverage and transient bound");
  }
}
