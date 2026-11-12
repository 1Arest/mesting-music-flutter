package com.mesting.music

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.app.Dialog
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.URI
import java.util.concurrent.atomic.AtomicInteger

/** On-device Passport web runtime. Dart owns the QR state machine; this bridge
 * owns only its WebView, SDK, scoped cookies and visible verification window.
 * No music account is committed here. No phone/OTP/token is logged. In
 * particular, NEVER clear the global CookieManager used by other platforms.
 */
class QishuiWebAuthPlugin : FlutterPlugin, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private val handler = Handler(Looper.getMainLooper())
    private var flow: Flow? = null
    private val ids = AtomicInteger()
    private val origin = "https://api.qishui.com/"
    private val assetRoot = "qishui-web-auth/"
    private val ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) SodaMusic/3.2.1 Chrome/136.0.7103.59 Electron/36.4.0 Safari/537.36"

    private class Flow(val id: String, val view: WebView) {
        val pending = mutableMapOf<Int, MethodChannel.Result>()
        var begin: MethodChannel.Result? = null
        var dialog: Dialog? = null
        var verification: MethodChannel.Result? = null
        var ready = false
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.mesting.music/qishui_web_auth").also { ch ->
            ch.setMethodCallHandler { call, result ->
                try {
                    val id = call.argument<String>("flowId").orEmpty()
                    if (!Regex("^[a-f0-9]{32}$").matches(id)) {
                        result.error("invalid_flow", "汽水登录会话无效", null)
                    } else if (call.method == "begin") {
                        val nonce = call.argument<String>("msToken").orEmpty()
                        if (!Regex("^[A-Za-z0-9_-]{118}==$" ).matches(nonce)) {
                            result.error("invalid_context", "汽水扫码会话初始化无效", null)
                        } else begin(id, nonce, result)
                    } else {
                        val current = flow
                        if (current == null || current.id != id) {
                            // An obsolete page closing must not close a newer login.
                            if (call.method == "close") result.success(null)
                            else result.error("cancelled", "汽水登录已取消", null)
                        } else when (call.method) {
                            "close" -> { close(); result.success(null) }
                            "cookies" -> result.success(cookieRows())
                            "openScanner" -> {
                                // Bind this user action to the genuine app's
                                // package; no other app receives the scan route.
                                val scanner = Intent(Intent.ACTION_VIEW,
                                    Uri.parse("luna://luna.com/scan_qr_code"))
                                    .setPackage("com.luna.music")
                                val opened = runCatching {
                                    val owner = activity ?: return@runCatching false
                                    owner.startActivity(scanner); true
                                }.getOrDefault(false)
                                result.success(opened)
                            }
                            "request" -> request(current, call.argument<String>("method").orEmpty(),
                                call.argument<String>("url").orEmpty(),
                                call.argument<Map<String, String>>("headers") ?: emptyMap(),
                                call.argument<String>("body"), result)
                            "verify" -> verify(current, call.argument<String>("decision").orEmpty(),
                                call.argument<String>("params").orEmpty(), result)
                            else -> result.notImplemented()
                        }
                    }
                } catch (_: Exception) { result.error("web_auth", "汽水登录组件未完成，请重新打开登录页", null) }
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configure(view: WebView) {
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            userAgentString = ua
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, true)
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(v: WebView, r: WebResourceRequest): Boolean = !firstParty(r.url.toString())
            override fun shouldInterceptRequest(v: WebView, r: WebResourceRequest): WebResourceResponse? {
                val u = runCatching { URI(r.url.toString()) }.getOrNull() ?: return null
                val name = u.path?.substringAfterLast('/') ?: return null
                val local = when {
                    u.host == "api.qishui.com" && name in setOf("react.js", "react-dom.js", "sdk-glue.js") -> name
                    name == "bdms.js" && u.host in setOf("lf-c-flwb.bytetos.com", "lf-headquarters-speed.yhgfb-cn-static.com", "api.qishui.com") -> name
                    else -> return null
                }
                return runCatching {
                    WebResourceResponse("text/javascript", "UTF-8", v.context.assets.open(assetRoot + local))
                }.getOrNull()
            }
        }
    }

    private fun firstParty(url: String): Boolean {
        val u = runCatching { URI(url) }.getOrNull() ?: return false
        return u.scheme == "https" && u.rawUserInfo == null && (u.port == -1 || u.port == 443) &&
            (u.host == "qishui.com" || u.host?.endsWith(".qishui.com") == true ||
             u.host == "douyin.com" || u.host?.endsWith(".douyin.com") == true ||
             u.host == "auth.zijieapi.com")
    }

    private fun begin(id: String, nonce: String, result: MethodChannel.Result) {
        close()
        val owner = activity ?: run { result.error("foreground", "请回到应用内再打开汽水登录", null); return }
        val view = WebView(owner)
        configure(view)
        val current = Flow(id, view).also { it.begin = result }
        flow = current
        // A hidden, attached view keeps the browser task alive while the
        // Flutter page displays the QR. It owns no audio renderer/service.
        (owner.window.decorView as? ViewGroup)?.addView(view, ViewGroup.LayoutParams(1, 1))
        view.visibility = View.INVISIBLE
        view.addJavascriptInterface(object {
            @JavascriptInterface fun complete(requestId: Int, nonce: String, value: String) {
                handler.post {
                    if (flow !== current || nonce != current.id) return@post
                    val reply = current.pending.remove(requestId) ?: return@post
                    if (value.length > 1024 * 1024) reply.error("large_response", "汽水登录响应超出限制", null)
                    else reply.success(value)
                }
            }
        }, "MestingQishuiReply")
        clearQishuiCookies {
            if (flow !== current) return@clearQishuiCookies
            if (cookieRows().any { it["name"] in setOf("sessionid", "sessionid_ss") }) {
                current.begin?.error("isolation", "本次汽水登录隔离未完成，请重试", null)
                current.begin = null
                close()
                return@clearQishuiCookies
            }
            val html = runCatching {
                owner.assets.open(assetRoot + "security_host.html").bufferedReader().use { it.readText() }
                    .replaceFirst("<head>", "<head><script>localStorage.clear();sessionStorage.clear();</script>")
            }.getOrElse {
                current.begin?.error("assets", "汽水登录组件读取失败，请重新打开登录页", null)
                current.begin = null; close(); return@clearQishuiCookies
            }
            view.loadDataWithBaseURL(origin, html, "text/html", "UTF-8", null)
            waitReady(current, nonce, System.currentTimeMillis() + 30_000)
        }
        handler.postDelayed({ if (flow === current && current.begin != null) close() }, 35_000)
    }

    private fun waitReady(current: Flow, nonce: String, deadline: Long) {
        if (flow !== current || current.begin == null) return
        if (System.currentTimeMillis() > deadline) {
            current.begin?.error("sdk_timeout", "汽水安全组件加载超时，请重试", null)
            current.begin = null; close(); return
        }
        current.view.evaluateJavascript("(window.bdms && window.__qishuiRequest) ? 'ready' : 'loading'") { raw ->
            if (flow !== current) return@evaluateJavascript
            if (raw == "\"ready\"") {
                // Align with myMusic: isolate this QR after bootstrap, then
                // seed the same provisional web nonce used in Passport query.
                // Later requests must retain the SDK's evolving runtime state.
                // Cleanup stays limited to Qishui; other platform jars survive.
                clearQishuiCookies {
                    if (flow !== current || current.begin == null) return@clearQishuiCookies
                    val seed = "(function(){try{localStorage.clear();" +
                        "localStorage.setItem('xmst',${JSONObject.quote(nonce)});" +
                        "localStorage.setItem('xmsty',${JSONObject.quote(nonce)});return 'ready';}" +
                        "catch(e){return 'failed';}})()"
                    current.view.evaluateJavascript(seed) seedDone@{ value ->
                        if (flow !== current || current.begin == null) return@seedDone
                        if (value != "\"ready\"") {
                            current.begin?.error("isolation", "汽水扫码会话初始化未完成", null)
                            current.begin = null; close()
                        } else {
                            current.ready = true; current.begin?.success(null); current.begin = null
                        }
                    }
                }
            } else handler.postDelayed({ waitReady(current, nonce, deadline) }, 200)
        }
    }

    /** Expire only cookies visible to the QR host, including common Passport
     * paths/domain variants. Never use removeAllCookies/removeSessionCookies.
     * Current platform credentials are in separate encrypted application jars.
     */
    private fun clearQishuiCookies(done: () -> Unit) {
        val manager = CookieManager.getInstance()
        val paths = listOf("/", "/passport", "/passport/", "/passport/web", "/passport/web/")
        val names = paths.flatMap { path ->
            manager.getCookie(origin.trimEnd('/') + path).orEmpty().split(';').mapNotNull {
                it.substringBefore('=').trim().takeIf { n -> Regex("^[A-Za-z0-9_-]{1,128}$").matches(n) }
            }
        }.toSet()
        val values = names.flatMap { name -> paths.flatMap { path ->
            listOf("", "; Domain=api.qishui.com", "; Domain=qishui.com", "; Domain=.qishui.com").map {
                "$name=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=$path; Secure$it"
            }
        } }
        if (values.isEmpty()) { done(); return }
        var remaining = values.size
        values.forEach { value -> manager.setCookie(origin, value) {
            remaining--; if (remaining == 0) { manager.flush(); handler.post(done) }
        } }
    }

    private fun cookieRows(): List<Map<String, String>> {
        val manager = CookieManager.getInstance()
        return manager.getCookie(origin).orEmpty().split(';').mapNotNull {
            val name = it.substringBefore('=').trim(); val value = it.substringAfter('=', "").trim()
            if (!Regex("^[A-Za-z0-9_-]{1,128}$").matches(name) || value.isEmpty()) null
            else mapOf("name" to name, "value" to value, "domain" to "api.qishui.com", "path" to "/",
                "hostOnly" to "true", "secure" to "true")
        }
    }

    private fun request(current: Flow, method: String, url: String, headers: Map<String, String>, body: String?, result: MethodChannel.Result) {
        val u = runCatching { URI(url) }.getOrNull()
        val allowed = u != null && firstParty(url) && (method == "GET" || method == "POST") &&
            ((u.host == "api.qishui.com" && u.path in setOf("/passport/web/get_qrcode/", "/passport/web/check_qrconnect/", "/luna/pc/me")) ||
             (method == "GET" && u.path.startsWith("/passport/") && u.path.contains("sso")))
        if (!current.ready || !allowed || url.length > 16_384 || (body?.length ?: 0) > 65_536 || current.pending.isNotEmpty()) {
            result.error("request_scope", "汽水登录请求无效或仍在处理中", null); return
        }
        val safeHeaders = JSONObject()
        val names = setOf("accept", "content-type", "x-ss-stub", "x-tt-passport-trace-id", "x-tt-passport-verify-portrait")
        headers.forEach { (name, value) -> if (name.lowercase() in names && value.length <= 512 && !value.contains('\n') && !value.contains('\r')) safeHeaders.put(name, value) }
        val spec = JSONObject().put("method", method).put("url", url).put("headers", safeHeaders).put("timeout", 25_000)
        if (body != null) spec.put("body", body)
        val id = ids.incrementAndGet()
        current.pending[id] = result
        // SDK adds its own dynamic browser signature. Do not manufacture
        // mobile signing headers, install IDs, or use an external signer.
        val script = "(function(){var done=function(v){MestingQishuiReply.complete($id,${JSONObject.quote(current.id)},JSON.stringify(v));};" +
            "try{Promise.resolve(window.__qishuiRequest($spec)).then(function(r){done({ok:true,result:r});}," +
            "function(){done({ok:false});});}catch(e){done({ok:false});}})()"
        current.view.evaluateJavascript(script, null)
        handler.postDelayed({ current.pending.remove(id)?.error("timeout", "汽水登录请求超时，请核对当前状态后重试", null) }, 30_000)
    }

    private fun verify(current: Flow, decision: String, params: String, result: MethodChannel.Result) {
        val owner = activity
        if (owner == null || decision.length > 65_536 || params.length > 32_768 || current.verification != null) {
            result.error("verify_scope", "当前无法打开汽水安全验证", null); return
        }
        val d = JSONObject(decision); val p = JSONObject(params)
        val view = WebView(owner); configure(view)
        val dialog = Dialog(owner)
        current.verification = result; current.dialog = dialog
        fun finish(success: Boolean) {
            if (flow !== current) return
            current.verification?.success(success); current.verification = null
            current.dialog = null; dialog.dismiss()
        }
        view.addJavascriptInterface(object {
            @JavascriptInterface fun complete(status: Boolean, message: String) { handler.post { finish(status) } }
        }, "__qishuiAndroidVerify")
        dialog.setContentView(view)
        dialog.setOnCancelListener { finish(false) }
        dialog.setOnDismissListener { view.removeJavascriptInterface("__qishuiAndroidVerify"); view.destroy() }
        dialog.show()
        dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        val html = owner.assets.open(assetRoot + "soda_verify.html").bufferedReader().use { it.readText() }
        view.loadDataWithBaseURL(origin, html, "text/html", "UTF-8", null)
        val deadline = System.currentTimeMillis() + 30_000
        fun ready() {
            if (flow !== current || current.verification == null) return
            view.evaluateJavascript("(window.bdms && window.__runSecondVerify) ? 'ready' : 'loading'") { raw ->
                if (flow !== current || current.verification == null) return@evaluateJavascript
                if (raw == "\"ready\"") view.evaluateJavascript("window.__runSecondVerify($d,{generalParams:$p})", null)
                else if (System.currentTimeMillis() < deadline) handler.postDelayed({ ready() }, 200)
                else finish(false)
            }
        }
        handler.postDelayed({ ready() }, 200)
        handler.postDelayed({ if (flow === current && current.dialog === dialog) finish(false) }, 300_000)
    }

    private fun close() {
        val current = flow ?: return
        flow = null
        current.begin?.error("cancelled", "汽水登录已取消", null)
        current.pending.values.forEach { it.error("cancelled", "汽水登录已取消", null) }
        current.pending.clear()
        current.verification?.success(false); current.verification = null
        current.dialog?.dismiss()
        current.view.removeJavascriptInterface("MestingQishuiReply")
        current.view.stopLoading()
        (current.view.parent as? ViewGroup)?.removeView(current.view)
        current.view.destroy()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { close(); channel?.setMethodCallHandler(null); channel = null }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { close(); activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { close(); activity = null }
}
