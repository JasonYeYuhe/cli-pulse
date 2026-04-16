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
import com.clipulse.android.data.model.CostForecast
import com.clipulse.android.ui.components.MetricCard
import com.clipulse.android.ui.components.formatCost
import com.clipulse.android.ui.components.formatUsage
import com.clipulse.android.util.ExportUtil
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background

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

                // Cost Forecast card
                state.costForecast?.let { forecast ->
                    Spacer(Modifier.height(12.dp))
                    ForecastCard(forecast)
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

@Composable
private fun ForecastCard(forecast: CostForecast) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.TrendingUp,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(R.string.forecast_title),
                    style = MaterialTheme.typography.titleMedium,
                )
            }

            if (!forecast.isReliable) {
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.forecast_insufficient),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column {
                    Text(
                        stringResource(R.string.forecast_month_end),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        formatCost(forecast.predictedMonthTotal),
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        stringResource(R.string.forecast_so_far),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        formatCost(forecast.actualToDate),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
            }

            // Progress bar
            Spacer(Modifier.height(8.dp))
            val progress = if (forecast.daysInMonth > 0) {
                forecast.currentDayOfMonth.toFloat() / forecast.daysInMonth
            } else 0f
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth().height(6.dp).clip(MaterialTheme.shapes.small),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
            )
            Text(
                "${forecast.currentDayOfMonth}/${forecast.daysInMonth} days",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 2.dp),
            )

            // Confidence range
            if (forecast.isReliable) {
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.forecast_confidence),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "${formatCost(forecast.lowerBound)} — ${formatCost(forecast.upperBound)}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}
