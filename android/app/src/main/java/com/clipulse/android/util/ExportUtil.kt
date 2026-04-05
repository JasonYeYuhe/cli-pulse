package com.clipulse.android.util

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.clipulse.android.data.model.ProviderUsage
import com.clipulse.android.data.model.SessionRecord
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter

object ExportUtil {

    fun exportSessionsCSV(context: Context, sessions: List<SessionRecord>): File? {
        val file = File(context.cacheDir, "cli-pulse-sessions.csv")
        return try {
            BufferedWriter(FileWriter(file)).use { w ->
                w.write("ID,Name,Provider,Project,Status,Usage,Cost,Requests,Errors,Started,Last Active\n")
                for (s in sessions) {
                    w.write("${esc(s.id)},${esc(s.name)},${esc(s.provider)},${esc(s.project)},")
                    w.write("${esc(s.status)},${s.totalUsage},${s.estimatedCost},")
                    w.write("${s.requests},${s.errorCount},${esc(s.startedAt)},${esc(s.lastActiveAt)}\n")
                }
            }
            file
        } catch (_: Exception) { null }
    }

    fun exportProviderSummaryCSV(context: Context, providers: List<ProviderUsage>): File? {
        val file = File(context.cacheDir, "cli-pulse-providers.csv")
        return try {
            BufferedWriter(FileWriter(file)).use { w ->
                w.write("Provider,Today Usage,Week Usage,Est. Cost,Remaining,Quota,Plan Type\n")
                for (p in providers) {
                    w.write("${esc(p.provider)},${p.todayUsage},${p.weekUsage},")
                    w.write("${p.estimatedCostWeek},${p.remaining ?: "N/A"},")
                    w.write("${p.quota ?: "N/A"},${esc(p.planType ?: "")}\n")
                }
            }
            file
        } catch (_: Exception) { null }
    }

    fun shareFile(context: Context, file: File, mimeType: String = "text/csv") {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Export CLI Pulse Data"))
    }

    private fun esc(value: String): String {
        return if (value.contains(",") || value.contains("\"") || value.contains("\n")) {
            "\"${value.replace("\"", "\"\"")}\""
        } else value
    }
}
