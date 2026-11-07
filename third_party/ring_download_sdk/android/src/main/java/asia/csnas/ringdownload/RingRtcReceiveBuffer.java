package asia.csnas.ringdownload;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;

/** Optional, per-engine actor. All methods run on the platform channel thread.
 * Native work is synchronous and bounded; close returns only after earlier
 * admitted operations have released their pinned duplicates. */
final class RingRtcReceiveBuffer {
  private static final boolean nativeAvailable;
  static {
    boolean loaded=false;
    try { System.loadLibrary("ring_receive_buffer"); loaded=true; }
    catch (LinkageError | SecurityException ignored) { /* Preserve normal downloads. */ }
    nativeAvailable=loaded;
  }
  private final HashSet<String> owners=new HashSet<>();
  private boolean attached=true;
  private static boolean valid(String owner) {return owner!=null && owner.matches("[a-f0-9]{32}");}
  boolean begin(String owner) {
    if(!attached || !nativeAvailable || !valid(owner) || owners.size()>=16)return false;
    return owners.add(owner);
  }
  boolean close(String owner) {return valid(owner) && owners.remove(owner);}
  void detach() {attached=false;owners.clear();}
  private static Map<String,Object> status(String code) {
    Map<String,Object> row=new HashMap<>();row.put("code",code);return row;
  }
  Map<String,Object> tune(String owner,List<?> bindings,long expiresAt) {
    if(!attached || !valid(owner) || !owners.contains(owner))return status("closed");
    long remaining=expiresAt-System.currentTimeMillis();
    if(remaining<=0 || remaining>250)return status("expired");
    if(bindings==null || bindings.isEmpty() || bindings.size()>8)return status("invalid");
    String[] addresses=new String[bindings.size()];int[] ports=new int[bindings.size()];
    for(int i=0;i<bindings.size();++i) {
      if(!(bindings.get(i) instanceof Map))return status("invalid");
      Map<?,?> binding=(Map<?,?>)bindings.get(i);
      Object address=binding.get("address"),port=binding.get("port");
      if(!(address instanceof String) || ((String)address).length()>45 ||
          !(port instanceof Integer || port instanceof Long))return status("invalid");
      long number=((Number)port).longValue();
      if(number<1 || number>65535)return status("invalid");
      addresses[i]=(String)address;ports[i]=(int)number;
    }
    final int[] values;
    try {values=nativeTune(addresses,ports);}
    catch (RuntimeException | LinkageError ignored) {return status("unavailable");}
    if(values==null || values.length!=7)return status("unavailable");
    for(int value:values)if(value<0)return status("unavailable");
    String code;
    if(values[0]!=0) {
      code=values[0]==1?"invalid":values[0]==3?"scan_limit":values[0]==4?"expired":"unavailable";
    } else if(values[5]>0 || values[4]>0 && values[2]>0)code="partial";
    else if(values[2]>0)code="adjusted";
    else if(values[4]>0)code="ambiguous";
    else if(values[1]>0)code="unchanged";
    else code="unmatched";
    Map<String,Object> result=status(code);
    result.put("matched",values[1]);result.put("adjusted",values[2]);
    result.put("unmatched",values[3]);result.put("ambiguous",values[4]);result.put("failed",values[5]);
    if(values[6]>0)result.put("minBufferBytes",values[6]);
    return result;
  }
  private static native int[] nativeTune(String[] addresses,int[] ports);
}
