package android.os;
/** Host-only scheduler marker; never part of the Android application. */
public final class Looper {
    private static final Looper MAIN = new Looper();
    public static Looper getMainLooper() { return MAIN; }
}
