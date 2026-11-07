package asia.csnas.ring_sdk_example;

/** Test-only own-FD bridge. Library is bundled by the private probe builder. */
public final class P8PDatagramOwners {
    static { System.loadLibrary("p8p_udp_owners"); }
    private P8PDatagramOwners() {}
    public static native String snapshotJson();
    public static native int datagramDescriptorCount();
}
