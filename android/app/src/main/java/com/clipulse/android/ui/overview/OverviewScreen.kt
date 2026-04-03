package com.clipulse.android.ui.overview

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.ui.components.MetricCard
import com.clipulse.android.ui.components.formatCost
import com.clipulse.android.ui.components.formatUsage

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OverviewScreen(
    viewModel: OverviewViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

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
            Text(
                "Overview",
                style = MaterialTheme.typography.headlineMedium,
            )
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
                        title = "Today's Usage",
                        value = formatUsage(d.totalUsageToday),
                        modifier = Modifier.weight(1f),
                    )
                    MetricCard(
                        title = "Est. Cost",
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
                        title = "Active Sessions",
                        value = d.activeSessions.toString(),
                        modifier = Modifier.weight(1f),
                    )
                    MetricCard(
                        title = "Online Devices",
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
                        title = "Requests",
                        value = d.totalRequestsToday.toString(),
                        modifier = Modifier.weight(1f),
                    )
                    MetricCard(
                        title = "Alerts",
                        value = d.unresolvedAlerts.toString(),
                        subtitle = when {
                            d.alertSummary.critical > 0 -> "${d.alertSummary.critical} critical"
                            d.alertSummary.warning > 0 -> "${d.alertSummary.warning} warnings"
                            else -> null
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            } else if (!state.isLoading) {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(48.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No data yet. Pair a device to start monitoring.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
