package asia.csnas.ring_sdk_example

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin

// Registered only by the private native acceptance build, never the SDK plugin.
class P8PNativeProbeActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Only this private, visible test window stays awake. HOME still
        // backgrounds the activity and exercises the real SDK lifecycle rule.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "p8p/native_probe_config")
            .setMethodCallHandler { call, result ->
                if (call.method == "fixture") {
                    result.success(mapOf(
                        "certificate" to intent.getStringExtra("p8p_fixture_certificate"),
                        "port" to intent.getIntExtra("p8p_fixture_port", 0),
                        "sharing" to intent.getBooleanExtra("p8p_sharing_probe", false),
                        "overlap" to intent.getBooleanExtra("p8p_receive_sharing_probe", false),
                        "directService" to intent.getBooleanExtra("p8p_direct_service", false),
                        "completionNonce" to intent.getStringExtra("p8p_completion_nonce"),
                    ))
                } else if (call.method == "udpOwnedBindings" || call.method == "udpOwnedDescriptorCount") {
                    try {
                        result.success(if (call.method == "udpOwnedBindings") {
                            P8PDatagramOwners.snapshotJson()
                        } else {
                            P8PDatagramOwners.datagramDescriptorCount()
                        })
                    } catch (failure: Exception) {
                        result.error("native_udp_owner_inspection_failed", failure.javaClass.simpleName,
                            mapOf("reason" to failure.message?.take(160)))
                    } catch (failure: LinkageError) {
                        result.error("native_udp_library_unavailable", failure.javaClass.simpleName,
                            mapOf("reason" to failure.message?.take(160)))
                    }
                } else if (call.method == "udpBindSelfCheck" || call.method == "udpBindProbe") {
                    try {
                        val observations = if (call.method == "udpBindSelfCheck") {
                            P8PUdpProbe.selfCheck()
                        } else {
                            P8PUdpProbe.probe(call.argument<List<Map<String, Any>>>("bindings"))
                        }
                        result.success(observations)
                    } catch (failure: Exception) {
                        result.error("native_udp_inspection_failed", failure.javaClass.simpleName,
                            mapOf("reason" to failure.message?.take(160)))
                    } catch (failure: LinkageError) {
                        result.error("native_udp_library_unavailable", failure.javaClass.simpleName,
                            mapOf("reason" to failure.message?.take(160)))
                    }
                } else if (call.method == "rtcBuffers") {
                    try {
                        val plugin = flutterEngine.plugins.get(FlutterWebRTCPlugin::class.java)
                            ?: error("Native RTC plugin is not registered")
                        fun field(owner: Any, name: String): Any {
                            val value = owner.javaClass.getDeclaredField(name)
                            value.isAccessible = true
                            return value.get(owner) ?: error("Native RTC owner missing")
                        }
                        val handler = field(plugin, "methodCallHandler")
                        val peers = field(handler, "mPeerConnectionObservers") as Map<*, *>
                        val buffers = peers.values.flatMap { peer ->
                            val channels = field(peer!!, "dataChannels") as Map<*, *>
                            channels.values.map { channel ->
                                // Read native state independently of Dart's
                                // event-cached getter; export no identifiers.
                                (channel!!.javaClass.getMethod("bufferedAmount")
                                    .invoke(channel) as Number).toLong()
                            }
                        }.sorted()
                        result.success(buffers)
                    } catch (failure: Exception) {
                        result.error("native_buffer_inspection_failed", failure.javaClass.simpleName, null)
                    }
                } else if (call.method == "rtcOwners") {
                    try {
                        val plugin = flutterEngine.plugins.get(FlutterWebRTCPlugin::class.java)
                            ?: error("Native RTC plugin is not registered")
                        fun field(owner: Any, name: String): Any {
                            val value = owner.javaClass.getDeclaredField(name)
                            value.isAccessible = true
                            return value.get(owner) ?: error("Native RTC owner missing")
                        }
                        // Private test-only introspection of the pinned plugin.
                        // Export counts only, never native IDs or network data.
                        val handler = field(plugin, "methodCallHandler")
                        val peers = field(handler, "mPeerConnectionObservers") as Map<*, *>
                        val channels = peers.values.sumOf {
                            (field(it!!, "dataChannels") as Map<*, *>).size
                        }
                        val observers = peers.values.sumOf {
                            (field(it!!, "dataChannelObservers") as Map<*, *>).size
                        }
                        result.success(mapOf("peerConnections" to peers.size,
                            "dataChannels" to channels, "channelObservers" to observers))
                    } catch (failure: Exception) {
                        result.error("native_owner_inspection_failed", failure.javaClass.simpleName, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
