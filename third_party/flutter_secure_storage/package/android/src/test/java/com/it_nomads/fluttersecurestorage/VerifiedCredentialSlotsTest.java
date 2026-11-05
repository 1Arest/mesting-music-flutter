package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

/** Transaction tests use synthetic values, not an imitation of hardware crypto. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class VerifiedCredentialSlotsTest {
    private static final String KEY = "mesting_music_platform_netease_session_v1";
    private Context context;
    private String metadata;
    private String prefix;
    private final Map<String, Integer> opens = new HashMap<>();
    private boolean failOld;
    private boolean failSecondOpen;

    @Before public void setup() {
        context = RuntimeEnvironment.getApplication();
        String id = UUID.randomUUID().toString().replace("-", "");
        metadata = "test_slot_pointers_" + id;
        prefix = "test_slot_" + id + "_";
        context.getSharedPreferences(VerifiedCredentialSlots.OLD_ARCHIVE, 0).edit().clear().commit();
    }

    private VerifiedCredentialSlots slots() {
        return new VerifiedCredentialSlots(context, FakeStore::new, metadata, prefix);
    }

    private final class FakeStore extends FlutterSecureStorage {
        FlutterSecureStorageConfig config;
        FakeStore(Context context) { super(context); }
        @Override public void initialize(FlutterSecureStorageConfig value, SecurePreferencesCallback<Void> callback) {
            config = value;
            String name = config.getEffectiveDataPrefsName();
            int count = opens.getOrDefault(name, 0) + 1; opens.put(name, count);
            if (failOld && name.equals(VerifiedCredentialSlots.OLD_ARCHIVE) ||
                    failSecondOpen && name.startsWith(prefix) && count >= 2) {
                callback.onError(new KeyPermanentlyInvalidatedException());
            } else callback.onSuccess(null);
        }
        @Override public String addPrefixToKey(String key) { return config.getSharedPreferencesKeyPrefix() + '_' + key; }
        @Override public void write(String key, String value) {
            context.getSharedPreferences(config.getEffectiveDataPrefsName(), 0).edit().putString(key, value).commit();
        }
        @Override public String read(String key) {
            return context.getSharedPreferences(config.getEffectiveDataPrefsName(), 0).getString(key, null);
        }
    }

    private static final class Outcome<T> implements SecurePreferencesCallback<T> {
        T value; Exception error; boolean finished;
        @Override public void onSuccess(T value) { this.value = value; finished = true; }
        @Override public void onError(Exception error) { this.error = error; finished = true; }
        void successful() { assertTrue(finished); assertNull(error); }
    }

    private String rawKey() {
        return new FlutterSecureStorageConfig(new HashMap<>()).getSharedPreferencesKeyPrefix() + '_' + KEY;
    }

    @Test public void emptyBrokenArchiveDoesNotOpenAnyCipher() {
        failOld = true;
        Outcome<String> read = new Outcome<>(); slots().read(KEY, read);
        read.successful(); assertNull(read.value); assertTrue(opens.isEmpty());
    }

    @Test public void existingUnreadableOverlayIsNotMistakenForAnEmptyAccount() {
        context.getSharedPreferences(VerifiedCredentialSlots.OLD_ARCHIVE, 0).edit().putString(rawKey(), "opaque-old").commit();
        failOld = true;
        Outcome<String> read = new Outcome<>(); slots().read(KEY, read);
        assertTrue(read.error instanceof KeyPermanentlyInvalidatedException);
        assertEquals("opaque-old", context.getSharedPreferences(VerifiedCredentialSlots.OLD_ARCHIVE, 0).getString(rawKey(), null));
    }

    @Test public void verifiedSaveNeverReadsFailedOldArchiveAndReopensBeforePublish() {
        context.getSharedPreferences(VerifiedCredentialSlots.OLD_ARCHIVE, 0).edit().putString(rawKey(), "opaque-old").commit();
        failOld = true;
        Outcome<Map<String, String>> save = new Outcome<>(); slots().save(KEY, "synthetic-new", save);
        save.successful(); String generation = save.value.get("generation");
        assertEquals(Integer.valueOf(2), opens.get(generation));
        assertFalse(opens.containsKey(VerifiedCredentialSlots.OLD_ARCHIVE));
        Outcome<String> restarted = new Outcome<>(); slots().read(KEY, restarted);
        restarted.successful(); assertEquals("synthetic-new", restarted.value);
        assertEquals("opaque-old", context.getSharedPreferences(VerifiedCredentialSlots.OLD_ARCHIVE, 0).getString(rawKey(), null));
    }

    @Test public void cachedWriteSuccessCannotPublishAnUnopenableNewSlot() {
        failSecondOpen = true;
        Outcome<Map<String, String>> save = new Outcome<>(); slots().save(KEY, "synthetic-new", save);
        assertTrue(save.error instanceof KeyPermanentlyInvalidatedException);
        assertFalse(context.getSharedPreferences(metadata, 0).contains(KEY));
    }

    @Test public void logoutTombstoneSurvivesNewRepositoryWithoutResurrectingOldData() {
        Outcome<Map<String, String>> save = new Outcome<>(); slots().save(KEY, "synthetic-new", save); save.successful();
        Outcome<Void> write = new Outcome<>(); slots().write(KEY, "{\"schema\":1,\"value\":null}", write); write.successful();
        Outcome<String> read = new Outcome<>(); slots().read(KEY, read); read.successful();
        assertEquals("{\"schema\":1,\"value\":null}", read.value);
    }

    @Test public void rollbackOnlyRestoresPointerAndCannotReplaceANewerLogin() {
        VerifiedCredentialSlots slots = slots();
        Outcome<Map<String, String>> first = new Outcome<>(); slots.save(KEY, "first", first); first.successful();
        Outcome<Map<String, String>> second = new Outcome<>(); slots.save(KEY, "second", second); second.successful();
        Outcome<Void> stale = new Outcome<>(); slots.rollback(KEY, first.value.get("generation"), first.value.get("previous"), stale);
        assertNotNull(stale.error);
        Outcome<Void> rollback = new Outcome<>(); slots.rollback(KEY, second.value.get("generation"), second.value.get("previous"), rollback); rollback.successful();
        Outcome<String> read = new Outcome<>(); slots().read(KEY, read); read.successful(); assertEquals("first", read.value);
    }

    @Test public void platformsKeepIndependentPointers() {
        String kugou = "mesting_music_platform_kugou_accounts_v2";
        Outcome<Map<String, String>> a = new Outcome<>(); slots().save(KEY, "netease", a); a.successful();
        Outcome<Map<String, String>> b = new Outcome<>(); slots().save(kugou, "kugou", b); b.successful();
        Outcome<Void> rollback = new Outcome<>(); slots().rollback(KEY, a.value.get("generation"), null, rollback); rollback.successful();
        Outcome<String> read = new Outcome<>(); slots().read(kugou, read); read.successful(); assertEquals("kugou", read.value);
    }

    @Test public void invalidPointerIsAnErrorRatherThanSilentLegacyFallback() {
        context.getSharedPreferences(metadata, 0).edit().putString(KEY, "unexpected-namespace").commit();
        Outcome<String> read = new Outcome<>(); slots().read(KEY, read);
        assertNotNull(read.error); assertTrue(opens.isEmpty());
    }
}
