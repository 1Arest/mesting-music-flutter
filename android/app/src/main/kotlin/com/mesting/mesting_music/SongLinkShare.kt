package com.mesting.music

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Native launch only. WeChat owns recipient selection and final confirmation.
 * Keep this independent from diagnostics, image saving and audio resolution. */
internal object SongLinkShare {
    fun openWeChat(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val uri = Uri.parse(url)
        if (url.length > 2048 || uri.scheme !in listOf("https", "http") ||
            uri.host.isNullOrBlank() || !uri.userInfo.isNullOrEmpty()) {
            result.error("invalid_url", "歌曲链接不可用", null)
            return
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
            setPackage("com.tencent.mm")
        }
        try {
            activity.startActivity(intent)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("wechat_unavailable", "请先安装微信，再分享给好友", null)
        } catch (_: Exception) {
            result.error("share_failed", "暂时无法打开微信，请稍后重试", null)
        }
    }
}
