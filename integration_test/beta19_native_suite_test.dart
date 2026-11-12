import 'beta19_device_performance_test.dart' as controls;
import 'beta19_scroll_benchmark_test.dart' as scrolling;

/// Target for the isolated native benchmark APK. The desktop runner must verify
/// its .benchmark application id and pass --keep-app-running to flutter drive.
void main() {
  scrolling.main();
  controls.main();
}
