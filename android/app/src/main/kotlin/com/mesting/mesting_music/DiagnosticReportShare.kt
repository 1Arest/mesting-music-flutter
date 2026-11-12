package com.mesting.music

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Exports only fixed private reports, never arbitrary caller files. */
object DiagnosticReportShare {
    private val worker = Executors.newSingleThreadExecutor()

    /** Each caller selects a fixed report contract, never a caller-owned path. */
    private enum class Report(
        val directory: String,
        val fileName: String,
        val clipLabel: String,
        val chooserTitle: String,
        val maximumBytes: Long?,
    ) {
        FLOW("flow_diagnostics", "mesting-flow-report.json", "Mesting flow report", "导出流畅度诊断 JSON", null),
        GLASS_LAB("glass_lab_diagnostics", "mesting-glass-lab-report.json", "Mesting glass lab report", "导出八场景实验报告", 16_777_216L),
        QISHUI("qishui_diagnostics", "mesting-qishui-report.json", "Mesting Qishui report", "导出汽水诊断 JSON", 1_048_576L),
        NETEASE_AD("netease_ad_diagnostics", "mesting-netease-ad-report.json", "Mesting NetEase ad configuration", "导出网易云广告配置 JSON", 65_536L),
    }

    fun share(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        shareFixed(activity, call, result, Report.FLOW)
    }

    /** A separate method and exact path keep the previous flow export intact. */
    fun shareQishui(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        shareFixed(activity, call, result, Report.QISHUI)
    }

    fun shareGlassLab(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        shareFixed(activity, call, result, Report.GLASS_LAB)
    }

    fun shareNeteaseAd(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        shareFixed(activity, call, result, Report.NETEASE_AD)
    }

    private fun shareFixed(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
        report: Report,
    ) {
        val input = call.argument<String>("path") ?: ""
        worker.execute {
          try {
            val source = File(input).canonicalFile
            val relativeDirectory = report.directory
            val fileName = report.fileName
            val support = File(activity.filesDir, relativeDirectory)
            // path_provider's Android support directory is context.filesDir.
            val expected = File(support, fileName).canonicalFile
            require(source == expected && source.isFile) { "invalid_report" }
            if (report.maximumBytes != null) {
                // Check both containment and size; neither a caller-selected
                // path nor a symlink can turn this into a private-file reader.
                val privateRoot = activity.filesDir.canonicalFile.path + File.separator
                require(expected.path.startsWith(privateRoot)) { "invalid_report" }
                val fixedLocation = File(
                    activity.filesDir.canonicalFile,
                    "$relativeDirectory/$fileName",
                ).absoluteFile
                require(expected == fixedLocation) { "invalid_report" }
                require(source.length() in 1L..report.maximumBytes) { "invalid_report" }
            }
            val directory = File(activity.cacheDir, "diagnostic_reports").apply { mkdirs() }
            val copy = File(directory, fileName)
            source.copyTo(copy, overwrite = true)
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.update_files", copy)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(
                    report.clipLabel, uri,
                )
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.runOnUiThread {
                try {
                    activity.startActivity(Intent.createChooser(
                        intent, report.chooserTitle,
                    ))
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
