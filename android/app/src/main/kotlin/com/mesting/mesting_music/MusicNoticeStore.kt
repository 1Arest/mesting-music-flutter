package com.mesting.music

import android.Manifest
import android.app.job.JobScheduler
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** One process-wide writer arbitrates UI and headless engines. Credentials never
 * enter this store: account scopes are one-way digests of the retained login.
 * Notification IDs/channels are separate from the existing media notification. */
object MusicNoticeStore {
    const val JOB_ID = 110121
    private const val TAG_PREFIX = "mesting_notice:"
    private const val INTERVAL = 15 * 60 * 1000L
    private var lease: String? = null
    private var leaseUntil = 0L
    private val platforms = setOf("netease", "kugou")
    private val kinds = mapOf("privateMessage" to "私信", "interaction" to "评论、赞与关注",
        "artist" to "关注歌手动态", "recommendation" to "新歌推荐")

    private fun prefs(context: Context) = context.getSharedPreferences("mesting_notices_v1", Context.MODE_PRIVATE)
    private fun read(context: Context) = runCatching {
        JSONObject(prefs(context).getString("state", "{}") ?: "{}")
    }.getOrElse { JSONObject() }
    private fun save(context: Context, state: JSONObject) {
        check(prefs(context).edit().putString("state", state.toString()).commit())
    }
    private fun objectAt(state: JSONObject, key: String): JSONObject = state.optJSONObject(key)
        ?: JSONObject().also { state.put(key, it) }
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    fun permitted(context: Context): Boolean = (Build.VERSION.SDK_INT < 33 ||
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        manager(context).areNotificationsEnabled()

    @Synchronized fun state(context: Context): Map<String, Any?> {
        val state = read(context)
        val owners = objectAt(state, "owners")
        val inbox = state.optJSONArray("inbox") ?: JSONArray()
        val visible = JSONArray()
        for (i in 0 until inbox.length()) {
            val row = inbox.optJSONObject(i) ?: continue
            if (row.optString("scope").isNotEmpty() &&
                row.optString("scope") == owners.optString(row.optString("platform"))) visible.put(row)
        }
        return mapOf("json" to state.put("inbox", visible).toString(), "permission" to permitted(context),
            "machine" to Build.MODEL, "scheduled" to (context.getSystemService(JobScheduler::class.java)
                .getPendingJob(JOB_ID) != null))
    }

    private fun cancelPlatform(context: Context, platform: String) {
        manager(context).activeNotifications.filter { it.tag?.startsWith("$TAG_PREFIX$platform:") == true }
            .forEach { manager(context).cancel(it.tag, it.id) }
    }

    private fun removePlatformData(state: JSONObject, platform: String, scope: String) {
        val feeds = objectAt(state, "feeds")
        if (scope.isNotEmpty()) feeds.keys().asSequence().toList()
            .filter { it.startsWith("$scope|") }.forEach { feeds.remove(it) }
        val inbox = state.optJSONArray("inbox") ?: JSONArray()
        val kept = JSONArray()
        for (i in 0 until inbox.length()) {
            val row = inbox.optJSONObject(i) ?: continue
            if (row.optString("platform") != platform) kept.put(row)
        }
        state.put("inbox", kept)
        if (state.optJSONObject("entry")?.optString("platform") == platform) state.remove("entry")
    }

    @Synchronized fun invalidate(context: Context, platform: String) {
        if (platform !in platforms) return
        val state = read(context)
        removePlatformData(state, platform, objectAt(state, "owners").optString(platform))
        objectAt(state, "owners").put(platform, "")
        state.put("generation", state.optLong("generation") + 1)
        save(context, state)
        cancelPlatform(context, platform)
        schedule(context)
    }

    /** A missing key means storage is unknown, not logged out. Only a successful
     * secure read may explicitly bind an empty owner and revoke that platform. */
    @Synchronized fun bind(context: Context, owners: Map<String, String>) {
        val state = read(context)
        val saved = objectAt(state, "owners")
        var changed = false
        for ((platform, scope) in owners) {
            if (platform !in platforms) continue
            if (objectAt(state, "errors").has("$platform:account")) {
                objectAt(state, "errors").remove("$platform:account")
                changed = true
            }
            if (saved.optString(platform) == scope) continue
            removePlatformData(state, platform, saved.optString(platform))
            saved.put(platform, scope)
            cancelPlatform(context, platform)
            changed = true
        }
        if (changed) {
            state.put("generation", state.optLong("generation") + 1)
            save(context, state)
        }
        schedule(context)
    }

    @Synchronized fun settings(context: Context, values: Map<String, Any?>) {
        val state = read(context)
        val settings = objectAt(state, "settings")
        for ((key, value) in values) if (value is Boolean &&
            (key == "enabled" || platforms.any { platform ->
                key == platform || kinds.keys.any { key == "$platform:$it" }
            })) settings.put(key, value)
        state.put("generation", state.optLong("generation") + 1)
        save(context, state)
        // Turning a group off also removes its already-delivered alerts.
        manager(context).activeNotifications.filter { notice ->
            notice.tag?.startsWith(TAG_PREFIX) == true &&
                (!settings.optBoolean("enabled", true) || platforms.any {
                    notice.tag?.startsWith("$TAG_PREFIX$it:") == true && !settings.optBoolean(it, true)
                } || kinds.keys.any { kind -> platforms.any { platform ->
                    notice.tag?.startsWith("$TAG_PREFIX$platform:$kind:") == true &&
                        !settings.optBoolean("$platform:$kind", true)
                } })
        }.forEach { manager(context).cancel(it.tag, it.id) }
        schedule(context)
    }

    @Synchronized fun begin(context: Context): Map<String, Any?>? {
        val state = read(context)
        if (!objectAt(state, "settings").optBoolean("enabled", true) || !permitted(context)) return null
        if (lease != null && System.currentTimeMillis() < leaseUntil) return null
        lease = UUID.randomUUID().toString()
        leaseUntil = System.currentTimeMillis() + 100_000L
        return mapOf("lease" to lease, "generation" to state.optLong("generation"), "json" to state.toString())
    }

    @Synchronized fun release(token: String?) { if (token == lease) lease = null }

    @Synchronized fun commit(context: Context, args: Map<String, Any?>): Boolean {
        val state = read(context)
        val platform = args["platform"] as? String ?: return false
        val scope = args["scope"] as? String ?: return false
        if (args["lease"] != lease || System.currentTimeMillis() > leaseUntil ||
            (args["generation"] as? Number)?.toLong() != state.optLong("generation") ||
            platform !in platforms || scope.isEmpty() || objectAt(state, "owners").optString(platform) != scope ||
            !permitted(context)) return false
        val settings = objectAt(state, "settings")
        if (!settings.optBoolean("enabled", true)) return false
        val feed = args["feed"] as? String ?: return false
        val cursor = args["state"] as? String ?: return false
        require(feed.length <= 120 && cursor.length <= 100_000)
        objectAt(state, "feeds").put("$scope|$feed", JSONObject(cursor))
        val fresh = (args["fresh"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
        val all = (args["events"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
        val inbox = state.optJSONArray("inbox") ?: JSONArray()
        val rows = linkedMapOf<String, JSONObject>()
        for (event in all) {
            val id = event["id"] as? String ?: continue
            val kind = event["kind"] as? String ?: continue
            if (id.length > 240 || kind !in kinds) continue
            val row = JSONObject(event).put("scope", scope).put("platform", platform)
            rows["$scope:$id"] = row
        }
        for (i in 0 until inbox.length()) {
            val row = inbox.optJSONObject(i) ?: continue
            val owner = row.optString("scope")
            if (owner != objectAt(state, "owners").optString(row.optString("platform"))) continue
            rows.putIfAbsent("$owner:${row.optString("id")}", row)
        }
        state.put("inbox", JSONArray(rows.values.take(100)))
        state.put("lastCheck", System.currentTimeMillis())
        objectAt(state, "errors").remove("$platform:$feed")
        save(context, state)
        // Group old backlog into at most four alerts per check. Every event is
        // still retained in the inbox; notification IDs remain deterministic.
        if (settings.optBoolean(platform, true)) for ((kind, events) in fresh.groupBy { it["kind"] as? String }) {
            if (kind !in kinds || !settings.optBoolean("$platform:$kind", true) || events.isEmpty()) continue
            val latest = events.maxByOrNull { (it["time"] as? Number)?.toLong() ?: 0 }!!
            post(context, platform, scope, kind!!, latest, events.size)
        }
        return true
    }

    private fun post(context: Context, platform: String, scope: String, kind: String, event: Map<*, *>, count: Int) {
        val channelId = "com.mesting.music.messages.$platform.$kind"
        val label = if (platform == "netease") "网易云" else "酷狗"
        if (Build.VERSION.SDK_INT >= 26) manager(context).createNotificationChannel(
            NotificationChannel(channelId, "$label · ${kinds[kind]}", NotificationManager.IMPORTANCE_HIGH)
                .apply { enableVibration(true); lockscreenVisibility = Notification.VISIBILITY_PRIVATE })
        val id = (event["id"] as? String ?: "").take(240)
        val intent = Intent(context, MusicEntryActivity::class.java)
            .setAction("com.mesting.music.OPEN_NOTICE")
            .putExtra("mesting_entry", "notifications").putExtra("platform", platform)
            .putExtra("scope", scope).putExtra("notice", id)
            .setData(android.net.Uri.parse("mesting://notice/${android.net.Uri.encode("$scope:$kind:$id")}"))
        val pending = PendingIntent.getActivity(context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val body = (event["body"] as? String ?: "有新消息").take(500)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId) else Notification.Builder(context)
        if (Build.VERSION.SDK_INT < 26) builder.setDefaults(Notification.DEFAULT_ALL)
        val notification = builder.setSmallIcon(R.drawable.ic_stat_mesting)
            .setContentTitle("$label · ${(event["title"] as? String ?: kinds[kind]).orEmpty().take(100)}")
            .setContentText(if (count > 1) "$body（另有 ${count - 1} 条）" else body)
            .setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(pending)
            .setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(if (kind == "privateMessage") Notification.CATEGORY_MESSAGE else Notification.CATEGORY_SOCIAL)
            .setOnlyAlertOnce(true).setPriority(Notification.PRIORITY_HIGH).build()
        runCatching { manager(context).notify("$TAG_PREFIX$platform:$kind:$id", 121, notification) }
    }

    @Synchronized fun error(context: Context, platform: String, feed: String) {
        if (platform !in platforms || feed.length > 120) return
        val state = read(context)
        // Only a closed status is persisted. Exceptions can contain signed URLs.
        objectAt(state, "errors").put("$platform:$feed", "读取未完成，保留上次记录")
        save(context, state)
    }

    @Synchronized fun schedule(context: Context) {
        val state = read(context)
        val settings = objectAt(state, "settings")
        val enabled = settings.optBoolean("enabled", true) && permitted(context) &&
            platforms.any { settings.optBoolean(it, true) && objectAt(state, "owners").optString(it).isNotEmpty() }
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (!enabled) { scheduler.cancel(JOB_ID); return }
        if (scheduler.getPendingJob(JOB_ID) == null) scheduler.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(context, MusicNoticeJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPeriodic(INTERVAL).setPersisted(true).build())
    }

    @Synchronized fun enqueue(context: Context, intent: Intent) {
        val action = intent.getStringExtra("mesting_entry")
        if (action !in setOf("favorites", "recognize", "search", "notifications")) return
        val state = read(context)
        val entry = JSONObject().put("action", action).put("id", UUID.randomUUID().toString())
        if (action == "notifications") {
            val platform = intent.getStringExtra("platform") ?: return
            val scope = intent.getStringExtra("scope") ?: return
            if (scope.isEmpty() || platform !in platforms || objectAt(state, "owners").optString(platform) != scope) return
            entry.put("platform", platform).put("scope", scope).put("notice", intent.getStringExtra("notice").orEmpty().take(240))
        }
        state.put("entry", entry)
        save(context, state)
    }

    @Synchronized fun entry(context: Context): String? = read(context).optJSONObject("entry")?.toString()
    @Synchronized fun acknowledge(context: Context, id: String) {
        val state = read(context)
        if (state.optJSONObject("entry")?.optString("id") == id) { state.remove("entry"); save(context, state) }
    }
    @Synchronized fun lastPlatform(context: Context, platform: String?) : String {
        val state = read(context)
        if (platform in platforms) { state.put("lastPlatform", platform); save(context, state) }
        return state.optString("lastPlatform", "kugou")
    }
}
