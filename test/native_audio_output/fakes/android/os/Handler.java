package android.os;
import java.util.ArrayDeque;
/** Explicit queue makes delayed observer/lifecycle races reproducible on the JVM. */
public final class Handler {
    private static final ArrayDeque<Runnable> TASKS = new ArrayDeque<>();
    public Handler(Looper looper) {}
    public boolean post(Runnable action) { TASKS.add(action); return true; }
    public static void drain() { while (!TASKS.isEmpty()) TASKS.remove().run(); }
}
