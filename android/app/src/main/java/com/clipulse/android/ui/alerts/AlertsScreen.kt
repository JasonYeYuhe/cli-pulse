package com.clipulse.android.ui.alerts

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Snooze
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.data.model.AlertRecord
import com.clipulse.android.data.model.AlertSeverity
import com.clipulse.android.ui.components.StatusBadge
import com.clipulse.android.ui.navigation.LocalSnackbarHostState
import com.clipulse.android.ui.theme.SeverityCritical
import com.clipulse.android.ui.theme.SeverityInfo
import com.clipulse.android.ui.theme.SeverityWarning

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlertsScreen(
    viewModel: AlertsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbar = LocalSnackbarHostState.current
    LaunchedEffect(state.error) {
        state.error?.let { snackbar.showSnackbar(it) }
    }

    PullToRefreshBox(
        isRefreshing = state.isLoading,
        onRefresh = { viewModel.refresh() },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text("Alerts", style = MaterialTheme.typography.headlineMedium)
                Spacer(Modifier.height(8.dp))
            }

            items(state.alerts, key = { it.id }) { alert ->
                AlertCard(
                    alert = alert,
                    onAcknowledge = { viewModel.acknowledge(alert.id) },
                    onResolve = { viewModel.resolve(alert.id) },
                    onSnooze = { viewModel.snooze(alert.id) },
                )
            }

            if (state.alerts.isEmpty() && !state.isLoading) {
                item {
                    Text(
                        "No alerts. All clear!",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(32.dp),
                    )
                }
            }
        }
    }
}

@Composable
fun AlertCard(
    alert: AlertRecord,
    onAcknowledge: () -> Unit,
    onResolve: () -> Unit,
    onSnooze: () -> Unit,
) {
    val severityColor = when (alert.alertSeverity) {
        AlertSeverity.Critical -> SeverityCritical
        AlertSeverity.Warning -> SeverityWarning
        AlertSeverity.Info -> SeverityInfo
        null -> SeverityInfo
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                StatusBadge(alert.severity, severityColor)
                if (alert.relatedProvider != null) {
                    Text(alert.relatedProvider, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(alert.title, style = MaterialTheme.typography.titleSmall)
            Spacer(Modifier.height(4.dp))
            Text(alert.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            if (!alert.isResolved) {
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (!alert.isRead) {
                        FilledTonalButton(onClick = onAcknowledge, contentPadding = PaddingValues(horizontal = 12.dp)) {
                            Text("Ack", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                    FilledTonalButton(onClick = onResolve, contentPadding = PaddingValues(horizontal = 12.dp)) {
                        Icon(Icons.Default.Check, contentDescription = "Resolve", modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Resolve", style = MaterialTheme.typography.labelSmall)
                    }
                    FilledTonalButton(onClick = onSnooze, contentPadding = PaddingValues(horizontal = 12.dp)) {
                        Icon(Icons.Default.Snooze, contentDescription = "Snooze", modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("1h", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
    }
}
