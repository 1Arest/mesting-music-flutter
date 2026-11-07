package asia.csnas.ring_sdk_example;

import android.system.ErrnoException;
import android.system.Os;
import android.system.OsConstants;
import java.io.FileDescriptor;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONObject;

/** Private acceptance activity only; never registered by the download SDK. */
public final class P8PUdpProbe {
    private P8PUdpProbe() {}

    private static FileDescriptor socket(InetAddress address) throws ErrnoException {
        boolean ipv4 = address instanceof Inet4Address;
        FileDescriptor descriptor = Os.socket(ipv4 ? OsConstants.AF_INET : OsConstants.AF_INET6,
                OsConstants.SOCK_DGRAM, OsConstants.IPPROTO_UDP);
        try {
            // An attempt must not share an existing RTC or control binding.
            Os.setsockoptInt(descriptor, OsConstants.SOL_SOCKET, OsConstants.SO_REUSEADDR, 0);
            if (!ipv4) {
                Os.setsockoptInt(descriptor, OsConstants.IPPROTO_IPV6, OsConstants.IPV6_V6ONLY, 1);
            }
            return descriptor;
        } catch (ErrnoException | RuntimeException | Error failure) {
            try { Os.close(descriptor); } catch (ErrnoException closing) { failure.addSuppressed(closing); }
            throw failure;
        }
    }

    private static boolean bindAvailable(InetAddress address, int port) throws Exception {
        FileDescriptor descriptor = socket(address);
        try {
            try {
                Os.bind(descriptor, address, port);
                return true;
            } catch (ErrnoException failure) {
                // Permission, unavailable interface and other errors cannot
                // masquerade as proof that an RTC socket owns this address.
                if (failure.errno == OsConstants.EADDRINUSE) return false;
                throw failure;
            }
        } finally {
            Os.close(descriptor);
        }
    }

    private static InetAddress numericAddress(Object input) throws Exception {
        if (!(input instanceof String)) throw new IllegalArgumentException("Numeric address required");
        String value = (String) input;
        if (value.length() > 80 || value.isEmpty()) {
            throw new IllegalArgumentException("Only bounded numeric addresses are accepted");
        }
        String[] parts = value.split("%", -1);
        if (parts.length > 2 || !parts[0].matches("[0-9A-Fa-f:.]+")
                || (parts.length == 2 && (!parts[0].contains(":")
                    || !parts[1].matches("[0-9]{1,10}")))) {
            throw new IllegalArgumentException("Only numeric addresses and IPv6 scope IDs are accepted");
        }
        String address = parts[0];
        // Requiring ':' or an IPv4 dotted quad prevents DNS/hex-name lookups.
        if (!address.contains(":") && !address.matches("[0-9]{1,3}(\\.[0-9]{1,3}){3}")) {
            throw new IllegalArgumentException("Only numeric IP addresses are accepted");
        }
        if (!address.contains(":")) {
            for (String octet : address.split("\\.")) {
                if (Integer.parseInt(octet) > 255) throw new IllegalArgumentException("Invalid IPv4 octet");
            }
        }
        return InetAddress.getByName(value);
    }

    private static Set<String> ownedKeys() throws Exception {
        String text = P8PDatagramOwners.snapshotJson();
        if (text == null || text.length() > 8192) throw new IllegalStateException("Invalid own-FD output");
        JSONArray values = new JSONArray(text);
        if (values.length() > 32) throw new IllegalStateException("Too many own-FD bindings");
        Set<String> result = new HashSet<>();
        int descriptorCount = P8PDatagramOwners.datagramDescriptorCount();
        if (descriptorCount < values.length() || descriptorCount > 2048) {
            throw new IllegalStateException("Invalid own datagram descriptor count");
        }
        result.add("@descriptor-count:" + descriptorCount);
        for (int i = 0; i < values.length(); i++) {
            JSONObject row = values.getJSONObject(i);
            if (row.length() != 3) throw new IllegalStateException("Unexpected own-FD fields");
            InetAddress ip = numericAddress(row.get("address"));
            Object input = row.get("port");
            if (!(input instanceof Integer) && !(input instanceof Long)) {
                throw new IllegalStateException("Invalid own-FD port type");
            }
            long port = ((Number) input).longValue();
            int family = ip instanceof Inet4Address ? 4 : 6;
            if (port < 1 || port > 65535 || row.getInt("family") != family
                    || !result.add(ip.getHostAddress() + ":" + port)) {
                throw new IllegalStateException("Invalid or duplicate own-FD binding");
            }
        }
        return result;
    }

    public static List<Map<String, Object>> probe(List<? extends Map<String, ?>> bindings)
            throws Exception {
        if (bindings == null || bindings.isEmpty() || bindings.size() > 32) {
            throw new IllegalArgumentException("One to 32 bindings required");
        }
        List<Map<String, Object>> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (Map<String, ?> binding : bindings) {
            if (binding == null || binding.size() != 2
                    || !binding.containsKey("address") || !binding.containsKey("port")) {
                throw new IllegalArgumentException("Unexpected binding fields");
            }
            InetAddress address = numericAddress(binding.get("address"));
            Object input = binding.get("port");
            if (!(input instanceof Integer) && !(input instanceof Long)) {
                throw new IllegalArgumentException("Integer port required");
            }
            long value = ((Number) input).longValue();
            if (value < 1 || value > 65535) throw new IllegalArgumentException("Invalid port");
            int port = (int) value;
            if (!seen.add(address.getHostAddress() + ":" + port)) {
                throw new IllegalArgumentException("Duplicate binding");
            }
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("address", address.getHostAddress());
            row.put("port", port);
            row.put("family", address instanceof Inet4Address ? 4 : 6);
            row.put("exclusiveBindSucceeded", bindAvailable(address, port));
            result.add(row);
        }
        return result;
    }

    public static List<Map<String, Object>> selfCheck() throws Exception {
        List<Map<String, Object>> result = new ArrayList<>();
        for (String text : new String[] {"127.0.0.1", "::1"}) {
            Set<String> baseline = ownedKeys();
            int baselineCount = P8PDatagramOwners.datagramDescriptorCount();
            InetAddress address = numericAddress(text);
            FileDescriptor held = socket(address);
            int port;
            try {
                if (P8PDatagramOwners.datagramDescriptorCount() != baselineCount + 1) {
                    throw new IllegalStateException("Actual unbound datagram FD was not observed");
                }
                Os.bind(held, address, 0);
                port = ((InetSocketAddress) Os.getsockname(held)).getPort();
                if (!ownedKeys().contains(address.getHostAddress() + ":" + port)) {
                    throw new IllegalStateException("Actual own descriptor was not observed");
                }
                if (bindAvailable(address, port)) {
                    throw new IllegalStateException("Held socket was not exclusive");
                }
            } finally {
                Os.close(held);
            }
            if (!bindAvailable(address, port)) {
                throw new IllegalStateException("Closed control socket remains occupied");
            }
            if (!ownedKeys().equals(baseline)) {
                throw new IllegalStateException("Control descriptors did not return to baseline");
            }
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("family", address instanceof Inet4Address ? 4 : 6);
            row.put("heldBindRejected", true);
            row.put("releasedBindSucceeded", true);
            row.put("ownDescriptorObserved", true);
            row.put("ownUnboundDescriptorObserved", true);
            row.put("ownDescriptorsReturnedToBaseline", true);
            result.add(row);
        }
        return result;
    }
}
