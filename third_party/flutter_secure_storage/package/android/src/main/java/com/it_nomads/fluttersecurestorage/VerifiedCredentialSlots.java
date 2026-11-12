package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.content.SharedPreferences;
import androidx.annotation.Keep;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Compatibility routing for verified logins whose old key cannot be opened.
 *
 * The normal store, aliases, algorithms and ciphertext are not changed. An empty
 * 54/55 archive is inspected without initializing its cipher. Only an explicit
 * verified login creates a fresh namespace. The non-secret pointer is published
 * after a second storage instance has unwrapped the persisted key and decrypted
 * the value. Old namespaces are retained, including on rollback and logout.
 *
 * One plugin worker serializes saves, writes and rollbacks. Bounded reads use a
 * separate worker so a stalled old key cannot block an explicit new login.
 */
@Keep
public final class VerifiedCredentialSlots {
    static final String OLD_ARCHIVE = "mesting_verified_recovery_v1";
    static final String SLOT_PREFIX = "mesting_verified_login_v2_";
    static final String POINTER_PREFS = "MestingVerifiedCredentialSlotsV2";

    interface StoreFactory { FlutterSecureStorage create(Context context); }
    private final Context context;
    private final StoreFactory factory;
    private final SharedPreferences pointers;
    private final String prefix;

    public VerifiedCredentialSlots(Context context) {
        this(context, FlutterSecureStorage::new, POINTER_PREFS, SLOT_PREFIX);
    }

    // Dependency injection keeps transaction tests independent of Android's
    // hardware KeyStore; device tests separately validate actual cryptography.
    VerifiedCredentialSlots(Context context, StoreFactory factory, String pointerName, String prefix) {
        this.context = context;
        this.factory = factory;
        this.pointers = context.getSharedPreferences(pointerName, Context.MODE_PRIVATE);
        this.prefix = prefix;
    }

    public void read(String key, SecurePreferencesCallback<String> callback) {
        try {
            String slot = pointers.getString(key, null);
            if (slot != null) {
                validateSlot(slot);
                readExisting(slot, key, true, callback);
            } else if (hasEntry(OLD_ARCHIVE, key)) {
                readExisting(OLD_ARCHIVE, key, true, callback);
            } else {
                // In particular, do not generate/unwrap a key just to discover
                // that the archive never contained this platform's login.
                callback.onSuccess(null);
            }
        } catch (Exception error) { callback.onError(error); }
    }

    public void save(String key, String value, SecurePreferencesCallback<Map<String, String>> callback) {
        try {
            final String previous = pointers.getString(key, null);
            if (previous != null) validateSlot(previous);
            final String slot = prefix + UUID.randomUUID().toString().replace("-", "");
            initializeNewSlot(slot);
            writeVerified(slot, key, value, new SecurePreferencesCallback<Void>() {
                @Override public void onSuccess(Void ignored) {
                    try {
                        if (!pointers.edit().putString(key, slot).commit()) throw new SecureCommitException();
                        Map<String, String> receipt = new HashMap<>();
                        receipt.put("generation", slot);
                        receipt.put("previous", previous);
                        callback.onSuccess(receipt);
                    } catch (Exception error) { callback.onError(error); }
                }
                @Override public void onError(Exception error) { callback.onError(error); }
            });
        } catch (Exception error) { callback.onError(error); }
    }

    public void write(String key, String value, SecurePreferencesCallback<Void> callback) {
        try {
            String slot = pointers.getString(key, null);
            if (slot != null) validateSlot(slot);
            else if (hasEntry(OLD_ARCHIVE, key)) slot = OLD_ARCHIVE;
            else throw new IOException("No authoritative credential slot");
            writeVerified(slot, key, value, callback);
        } catch (Exception error) { callback.onError(error); }
    }

    public void rollback(String key, String generation, String previous,
            SecurePreferencesCallback<Void> callback) {
        try {
            validateSlot(generation);
            if (previous != null) validateSlot(previous);
            // Never let a stale rollback replace a newer completed login.
            if (!generation.equals(pointers.getString(key, null))) {
                throw new IOException("Credential pointer changed");
            }
            SharedPreferences.Editor edit = pointers.edit();
            if (previous == null) edit.remove(key); else edit.putString(key, previous);
            if (!edit.commit()) throw new SecureCommitException();
            callback.onSuccess(null);
        } catch (Exception error) { callback.onError(error); }
    }

    /** Reopen a regular 50/51 write without reusing its cached AES key. */
    public void verifyPrimary(FlutterSecureStorageConfig config, String key, String expected,
            SecurePreferencesCallback<Void> callback) {
        open(config, new SecurePreferencesCallback<FlutterSecureStorage>() {
            @Override public void onSuccess(FlutterSecureStorage store) {
                try {
                    if (!expected.equals(store.read(store.addPrefixToKey(key)))) {
                        throw new IOException("Credential reopen mismatch");
                    }
                    callback.onSuccess(null);
                } catch (Exception error) { callback.onError(error); }
            }
            @Override public void onError(Exception error) { callback.onError(error); }
        });
    }

    private void writeVerified(String slot, String key, String value,
            SecurePreferencesCallback<Void> callback) {
        final FlutterSecureStorageConfig config = config(slot);
        open(config, new SecurePreferencesCallback<FlutterSecureStorage>() {
            @Override public void onSuccess(FlutterSecureStorage store) {
                try { store.write(store.addPrefixToKey(key), value); }
                catch (Exception error) { callback.onError(error); return; }
                // A new instance is essential. Reading with `store` would only
                // prove that the in-memory AES key can decrypt its own write.
                verifyPrimary(config, key, value, callback);
            }
            @Override public void onError(Exception error) { callback.onError(error); }
        });
    }

    private void readExisting(String slot, String key, boolean required,
            SecurePreferencesCallback<String> callback) {
        if (!hasEntry(slot, key)) {
            if (required) callback.onError(new IOException("Credential slot entry missing"));
            else callback.onSuccess(null);
            return;
        }
        open(config(slot), new SecurePreferencesCallback<FlutterSecureStorage>() {
            @Override public void onSuccess(FlutterSecureStorage store) {
                try {
                    String value = store.read(store.addPrefixToKey(key));
                    if (value == null) throw new IOException("Credential slot entry missing");
                    callback.onSuccess(value);
                }
                catch (Exception error) { callback.onError(error); }
            }
            @Override public void onError(Exception error) { callback.onError(error); }
        });
    }

    private boolean hasEntry(String slot, String key) {
        FlutterSecureStorageConfig config = config(slot);
        return context.getSharedPreferences(config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE)
            .contains(config.getSharedPreferencesKeyPrefix() + '_' + key);
    }

    private FlutterSecureStorageConfig config(String slot) {
        Map<String, Object> options = new HashMap<>();
        options.put("storageNamespace", slot);
        options.put("resetOnError", "false");
        // A failed same-algorithm key is not an algorithm migration. Preserve it
        // and return its actual failure instead of attempting destructive repair.
        options.put("migrateOnAlgorithmChange", "false");
        return new FlutterSecureStorageConfig(options);
    }

    private void initializeNewSlot(String slot) throws IOException {
        FlutterSecureStorageConfig config = config(slot);
        if (!context.getSharedPreferences(slot, Context.MODE_PRIVATE).getAll().isEmpty() ||
                !context.getSharedPreferences(config.getEffectiveKeyStoragePrefsName(), Context.MODE_PRIVATE).getAll().isEmpty()) {
            throw new IOException("New credential slot collision");
        }
        // This is a brand-new empty store, never a migration of old ciphertext.
        // Declare its existing 50/51 algorithms before creating its first key.
        SharedPreferences.Editor edit = new NamespacedConfigSource(context, slot).edit();
        edit.putString("FlutterSecureSAlgorithmKey", "RSA_ECB_OAEPwithSHA_256andMGF1Padding");
        edit.putString("FlutterSecureSAlgorithmStorage", "AES_GCM_NoPadding");
        edit.putBoolean("ENCRYPTED_PREFERENCES_MIGRATED", true);
        if (!edit.commit()) throw new SecureCommitException();
    }

    private void validateSlot(String slot) throws IOException {
        if (slot == null || !slot.startsWith(prefix) || !slot.substring(prefix.length()).matches("[a-f0-9]{32}")) {
            throw new IOException("Invalid credential pointer");
        }
    }

    private void open(FlutterSecureStorageConfig config, SecurePreferencesCallback<FlutterSecureStorage> callback) {
        final FlutterSecureStorage store = factory.create(context);
        store.initialize(config, new SecurePreferencesCallback<Void>() {
            @Override public void onSuccess(Void ignored) { callback.onSuccess(store); }
            @Override public void onError(Exception error) { callback.onError(error); }
        });
    }
}
