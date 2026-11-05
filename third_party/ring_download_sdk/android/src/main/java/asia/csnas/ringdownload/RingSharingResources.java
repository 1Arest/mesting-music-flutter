package asia.csnas.ringdownload;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Handler;
import android.os.PowerManager;
import io.flutter.plugin.common.EventChannel;
import java.util.HashMap;
import java.util.Map;
import java.util.function.Supplier;

/** Per-engine observations only. No service, wake lock, settings write or new
 * permission. Dart stops listening outside the authorized foreground lifetime. */
final class RingSharingResources implements EventChannel.StreamHandler {
  private final Context context;
  private final Handler main;
  private final Supplier<String> network;
  private final PowerManager power;
  private EventChannel.EventSink sink;
  private BroadcastReceiver receiver;
  private Runnable removeThermal;
  private Map<String, Object> last;
  private int generation;

  RingSharingResources(Context context, Handler main, Supplier<String> network) {
    this.context = context;
    this.main = main;
    this.network = network;
    this.power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
  }

  Map<String, Object> snapshot() {
    Map<String, Object> facts = new HashMap<>();
    facts.put("network", network.get());
    facts.put("observing", receiver != null &&
        (Build.VERSION.SDK_INT < 29 || removeThermal != null));
    facts.put("battery_percent", null);
    facts.put("temperature_deci_c", null);
    facts.put("battery_healthy", null);
    facts.put("power_save", null);
    facts.put("thermal_status", null);
    facts.put("thermal_supported", Build.VERSION.SDK_INT >= 29);
    try {
      IntentFilter filter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
      Intent battery = Build.VERSION.SDK_INT >= 33
          ? context.registerReceiver(null, filter, Context.RECEIVER_NOT_EXPORTED)
          : context.registerReceiver(null, filter);
      if (battery != null && battery.getBooleanExtra(BatteryManager.EXTRA_PRESENT, false)) {
        int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        if (scale > 0 && level >= 0 && level <= scale) {
          facts.put("battery_percent", (int) Math.floor(100.0 * level / scale));
        }
        int temperature = battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1);
        if (temperature > 0 && temperature < 1000) {
          facts.put("temperature_deci_c", temperature);
        }
        facts.put("battery_healthy", battery.getIntExtra(BatteryManager.EXTRA_HEALTH,
            BatteryManager.BATTERY_HEALTH_UNKNOWN) == BatteryManager.BATTERY_HEALTH_GOOD);
      }
      if (power != null) {
        facts.put("power_save", power.isPowerSaveMode());
        if (Build.VERSION.SDK_INT >= 29) facts.put("thermal_status", power.getCurrentThermalStatus());
      }
    } catch (RuntimeException ignored) {
      // Nullable facts stay unknown. An observation failure never grants upload.
    }
    return facts;
  }

  @Override public void onListen(Object arguments, EventChannel.EventSink next) {
    stop();
    sink = next;
    final int owner = generation;
    receiver = new BroadcastReceiver() {
      @Override public void onReceive(Context ignored, Intent intent) { emit(owner, next); }
    };
    IntentFilter filter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
    filter.addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED);
    try {
      if (Build.VERSION.SDK_INT >= 33) {
        context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
      } else context.registerReceiver(receiver, filter);
    } catch (RuntimeException ignored) { receiver = null; }
    if (Build.VERSION.SDK_INT >= 29 && power != null) {
      try { removeThermal = Thermal29.listen(power, main, () -> emit(owner, next)); }
      catch (RuntimeException ignored) { removeThermal = null; }
    }
    emit(owner, next);
  }

  private void emit(int owner, EventChannel.EventSink target) {
    main.post(() -> {
      if (owner != generation || sink != target) return;
      Map<String, Object> facts = snapshot();
      if (!facts.equals(last)) { last = facts; target.success(facts); }
    });
  }

  @Override public void onCancel(Object arguments) { stop(); }
  void stop() {
    generation++;
    sink = null;
    last = null;
    if (receiver != null) {
      try { context.unregisterReceiver(receiver); } catch (RuntimeException ignored) { }
      receiver = null;
    }
    if (removeThermal != null) {
      try { removeThermal.run(); } catch (RuntimeException ignored) { }
      removeThermal = null;
    }
  }

  // Keep API29-only listener types out of the API24 owner's field signatures.
  private static final class Thermal29 {
    static Runnable listen(PowerManager power, Handler main, Runnable changed) {
      PowerManager.OnThermalStatusChangedListener listener = status -> changed.run();
      power.addThermalStatusListener(command -> main.post(command), listener);
      return () -> power.removeThermalStatusListener(listener);
    }
  }
}
