package com.mesting.music

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Exports only the runner's fixed private report, never arbitrary caller files. */
object DiagnosticReportShare {
    private val worker = Executors.newSingleThreadExecutor()

    fun share(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        val input = call.argument<String>("path") ?: ""
        worker.execute {
          try {
            val source = File(input).canonicalFile
            val support = File(activity.applicationInfo.dataDir, "files/flow_diagnostics")
            // path_provider's Android support directory is context.filesDir.
            val expected = File(support, "mesting-flow-report.json").canonicalFile
            require(source == expected && source.isFile) { "invalid_report" }
            val directory = File(activity.cacheDir, "diagnostic_reports").apply { mkdirs() }
            val copy = File(directory, "mesting-flow-report.json")
            source.copyTo(copy, overwrite = true)
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.update_files", copy)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri("Mesting flow report", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.runOnUiThread {
                try {
                    activity.startActivity(Intent.createChooser(intent, "导出流畅度诊断 JSON"))
                    result.success(null)
                } catch (_: Exception) {
                    result.error("diagnostic_export_failed", "诊断文件未能导出", null)
                }
            }
          } catch (_: Exception) {
            // Do not disclose private paths or exception text to reports/logs.
            activity.runOnUiThread {
                result.error("diagnostic_export_failed", "诊断文件未能导出", null)
            }
          }
        }
    }
}
