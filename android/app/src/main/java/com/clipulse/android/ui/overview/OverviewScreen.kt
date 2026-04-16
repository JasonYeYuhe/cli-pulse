package com.clipulse.android.ui.overview

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.R
import com.clipulse.android.ui.components.MetricCard
import com.clipulse.android.ui.components.formatCost
import com.clipulse.android.ui.components.formatUsage
import com.clipulse.android.util.ExportUtil
import androidx.compose.material.icons.filled.Analytics

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OverviewScreen(
    viewModel: OverviewViewModel = hiltViewModel(),
    onCostAnalysis: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var showExportMenu by remember { mutableStateOf(false) }

    PullToRefreshBox(
        isRefreshing = state.isLoading,
        onRefresh = { viewModel.refresh() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    stringResource(R.string.tab_overview),
                    style = MaterialTheme.typography.headlineMedium,
                )
                Box {
                    IconButton(onClick = { showExportMenu = true }) {
                        Icon(Icons.Default.FileDownload, contentDescription = stringResource(R.string.export_data))
                    }
                    DropdownMenu(expanded = showExportMenu, onDismissRequest = { showExportMenu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.export_sessions)) },
                            onClick = {
                                showExportMenu = false
                                val sessions = viewModel.getSessions()
                                ExportUtil.exportSessionsCSV(context, sessions)?.let { ExportUtil.shareFile(context, it) }
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.export_providers)) },
                            onClick = {
                                showExportMenu = false
                                val providers = viewModel.getProviders()
                                ExportUtil.exportProviderSummaryCSV(context, providers)?.let { ExportUtil.shareFile(context, it) }
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.export_alerts)) },
                            onClick = {
                                showExportMenu = false
                                val alerts = viewModel.getAlerts()
                                ExportUtil.exportAlertsCSV(context, alerts)?.let { ExportUtil.shareFile(context, it) }
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.export_cost_report)) },
                            onClick = {
                                showExportMenu = false
                                val usage = viewModel.getDailyUsage()
                                ExportUtil.exportCostReportCSV(context, usage)?.let { ExportUtil.shareFile(context, it) }
                            },
                        )
                    }
                }
            }
            Spacer(Modifier.height(16.dp))

            state.error?.let { error ->
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        error,
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
                Spacer(Modifier.height(16.dp))
            }

            val d = state.dashboard
            if (d != null) {
                // Top metrics row
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    MetricCard(
                        title = stringResource(R.string.today_usage),
                        value = formatUsage(d.totalUsageToday),
                        modifier = Modifier.weight(1f),
                    )
                    MetricCard(
                        title = stringResource(R.string.estimated_cost),
                        value = formatCost(d.totalEstimatedCostToday),
                        modifier = Modifier.weight(1f),
                    )
                }
                Spacer(Modifier.height(12.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    MetricCard(
                        title = stringResource(R.string.active_sessions),
                        value = d.activeSessions.toString(),
                        modifier = Modifier.weight(1f),
                    )
                    MetricCard(
                        title = stringResource(R.string.online_devices),
                        value = d.onlineDevices.toString(),
                        modifier = Modifier.weight(1f),
                    )
                }
                Spacer(Modifier.height(12.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    MetricCard(
                        title = stringResource(R.string.overview_requests),
                        value = d.totalRequestsToday.toString(),
                        modifier = Modifier.weight(1f),
                    )
                    MetricCard(
                        title = stringResource(R.string.unresolved_alerts),
                        value = d.unresolvedAlerts.toString(),
                        subtitle = when {
                            d.alertSummary.critical > 0 -> "${d.alertSummary.critical} critical"
                            d.alertSummary.warning > 0 -> "${d.alertSummary.warning} warnings"
                            else -> null
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
                Spacer(Modifier.height(16.dp))

                // Cost Analysis entry point
                OutlinedButton(
                    onClick = onCostAnalysis,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Analytics, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.cost_analysis_title))
                }
            } else if (!state.isLoading) {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(48.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        stringResource(R.string.overview_no_data),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
