package com.it_nomads.fluttersecurestorage;

import android.content.Context;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class FlutterSecureStoragePlugin implements MethodCallHandler, FlutterPlugin {

    private static final String TAG = "FlutterSecureStoragePlugin";
    private MethodChannel channel;
    private Context applicationContext;
    private final Map<String, FlutterSecureStorage> storagesBySharedPreferencesName = new HashMap<>();
    // Each fully isolated namespace owns one serial queue. A stalled legacy
    // KeyStore operation cannot block a verified login in the recovery namespace.
    // Calls sharing a cipher/preferences namespace remain strictly ordered.
    private final Map<String, HandlerThread> workers = new HashMap<>();

    public void initInstance(BinaryMessenger messenger, Context context) {
        try {
            applicationContext = context.getApplicationContext();

            channel = new MethodChannel(messenger, "plugins.it_nomads.com/flutter_secure_storage");
            channel.setMethodCallHandler(this);
        } catch (Exception e) {
            Log.e(TAG, "Registration failed", e);
        }
    }

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        initInstance(binding.getBinaryMessenger(), binding.getApplicationContext());
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            synchronized (workers) {
                for (HandlerThread worker : workers.values()) worker.quitSafely();
                workers.clear();
            }

            channel.setMethodCallHandler(null);
            channel = null;
        }
        synchronized (storagesBySharedPreferencesName) {
            storagesBySharedPreferencesName.clear();
        }
        applicationContext = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result rawResult) {
        MethodResultWrapper result = new MethodResultWrapper(rawResult);
        try {
            Map<String, Object> options = call.argument("options");
            FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(
                    options == null ? new HashMap<>() : options);
            String name = config.hasStorageNamespace()
                    ? "ns:" + config.getStorageNamespace() : config.getSharedPreferencesName();
            synchronized (workers) {
                HandlerThread worker = workers.get(name);
                if (worker == null) {
                    if (workers.size() >= 8) throw new IllegalStateException("Namespace capacity");
                    worker = new HandlerThread("mesting.secure." + workers.size());
                    worker.start();
                    workers.put(name, worker);
                }
                new Handler(worker.getLooper()).post(new MethodRunner(call, result));
            }
        } catch (Exception error) {
            result.error("mesting_storage", "Secure operation unavailable",
                    java.util.Collections.singletonMap("family", StorageErrorFamily.of(error)));
        }
    }

    @SuppressWarnings("unchecked")
    private static String getKeyFromCall(FlutterSecureStorage storage, MethodCall call) {
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        String key = (String) arguments.get("key");
        return storage.addPrefixToKey(key);
    }

    @SuppressWarnings("unchecked")
    private static String getValueFromCall(MethodCall call) {
        Map<String, Object> arguments = (Map<String, Object>) call.arguments;
        return (String) arguments.get("value");
    }

    private FlutterSecureStorage getOrCreateStorage(FlutterSecureStorageConfig config) {
        // Use "ns:" prefix for storageNamespace to avoid collisions with legacy
        // sharedPreferencesName keys in the map.
        final String name = config.hasStorageNamespace()
                ? "ns:" + config.getStorageNamespace()
                : config.getSharedPreferencesName();
        synchronized (storagesBySharedPreferencesName) {
            FlutterSecureStorage existing = storagesBySharedPreferencesName.get(name);
            if (existing != null) {
                return existing;
            }
            FlutterSecureStorage created = new FlutterSecureStorage(applicationContext);
            storagesBySharedPreferencesName.put(name, created);
            return created;
        }
    }

    /**
     * MethodChannel.Result wrapper that responds on the platform thread.
     */
    static class MethodResultWrapper implements Result {

        private final Result methodResult;
        private final Handler handler = new Handler(Looper.getMainLooper());

        MethodResultWrapper(Result methodResult) {
            this.methodResult = methodResult;
        }

        @Override
        public void success(final Object result) {
            handler.post(() -> methodResult.success(result));
        }

        @Override
        public void error(@NonNull final String errorCode, final String errorMessage, final Object errorDetails) {
            handler.post(() -> methodResult.error(errorCode, errorMessage, errorDetails));
        }

        @Override
        public void notImplemented() {
            handler.post(methodResult::notImplemented);
        }
    }

    /**
     * Wraps the functionality of onMethodCall() in a Runnable for execution in the worker thread.
     */
    class MethodRunner implements Runnable {
        private final MethodCall call;
        private final Result result;

        MethodRunner(MethodCall call, Result result) {
            this.call = call;
            this.result = result;
        }

        @SuppressWarnings("unchecked")
        @Override
        public void run() {
            // Guard MethodChannel payload before initialize(); funnel unexpected exceptions to result.error.
            try {
                if (call == null || call.arguments == null) {
                    handleException(new IllegalArgumentException("Method call arguments are null"));
                    return;
                }
                if (!(call.arguments instanceof Map)) {
                    handleException(new IllegalArgumentException("Method call arguments must be a Map"));
                    return;
                }
                Map<String, Object> args = (Map<String, Object>) call.arguments;
                Object rawOptions = args.get("options");
                Map<String, Object> options;
                if (rawOptions instanceof Map) {
                    options = (Map<String, Object>) rawOptions;
                } else {
                    options = new HashMap<>();
                }
                FlutterSecureStorageConfig config = new FlutterSecureStorageConfig(options);
                FlutterSecureStorage secureStorage = getOrCreateStorage(config);

                secureStorage.initialize(config, new SecurePreferencesCallback<>() {
                @Override
                public void onSuccess(Void unused) {
                    try {
                        switch (call.method) {
                            case "write": {
                                String key = getKeyFromCall(secureStorage, call);
                                String value = getValueFromCall(call);

                                if (value != null) {
                                    secureStorage.write(key, value);
                                    result.success(null);
                                } else {
                                    result.error("null", null, null);
                                }
                                break;
                            }
                            case "read": {
                                String key = getKeyFromCall(secureStorage, call);

                                if (secureStorage.containsKey(key)) {
                                    String value = secureStorage.read(key);
                                    result.success(value);
                                } else {
                                    result.success(null);
                                }
                                break;
                            }
                            case "readAll": {
                                result.success(secureStorage.readAll());
                                break;
                            }
                            case "containsKey": {
                                String key = getKeyFromCall(secureStorage, call);

                                boolean containsKey = secureStorage.containsKey(key);
                                result.success(containsKey);
                                break;
                            }
                            case "delete": {
                                String key = getKeyFromCall(secureStorage, call);

                                secureStorage.delete(key);
                                result.success(null);
                                break;
                            }
                            case "deleteAll": {
                                secureStorage.deleteAll();
                                result.success(null);
                                break;
                            }
                            case "isBiometricAvailable": {
                                boolean available = secureStorage.isBiometricAvailable();
                                result.success(available);
                                break;
                            }
                            case "isDeviceSecure": {
                                boolean secure = secureStorage.isDeviceSecure();
                                result.success(secure);
                                break;
                            }
                            default:
                                result.notImplemented();
                                break;
                        }
                    } catch (Exception e) {
                        if (config.shouldDeleteOnFailure()) {
                            try {
                                secureStorage.deleteAll();
                                result.success("Data has been reset");
                            } catch (Exception ex) {
                                handleException(ex);
                            }
                        } else {
                            handleException(e);
                        }
                    }
                }

                @Override
                public void onError(Exception e) {
                    handleException(e);
                }
            });
            } catch (Exception e) {
                handleException(e);
            }
        }


        private void handleException(Exception e) {
            // Native messages/stacks can contain keys and decrypted values.
            // Only the independently testable closed family crosses to Dart.
            result.error("mesting_storage", "Secure operation failed",
                    java.util.Collections.singletonMap("family", StorageErrorFamily.of(e)));
        }
    }
}
