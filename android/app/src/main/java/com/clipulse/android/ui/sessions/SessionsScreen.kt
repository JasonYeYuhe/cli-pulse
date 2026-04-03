package com.clipulse.android.ui.sessions

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.data.model.SessionRecord
import com.clipulse.android.data.model.SessionStatus
import com.clipulse.android.ui.components.StatusBadge
import com.clipulse.android.ui.components.formatCost
import com.clipulse.android.ui.components.formatUsage
import com.clipulse.android.ui.theme.PulseError
import com.clipulse.android.ui.theme.PulseSuccess
import com.clipulse.android.ui.theme.PulseWarning
import com.clipulse.android.ui.theme.providerColor

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionsScreen(
    viewModel: SessionsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

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
                Text("Sessions", style = MaterialTheme.typography.headlineMedium)
                Spacer(Modifier.height(8.dp))
            }

            state.error?.let { error ->
                item {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer,
                        ),
                    ) {
                        Text(error, modifier = Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onErrorContainer)
                    }
                }
            }

            items(state.sessions, key = { it.id }) { session ->
                SessionCard(session)
            }

            if (state.sessions.isEmpty() && !state.isLoading && state.error == null) {
                item {
                    Text(
                        "No sessions yet.",
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
fun SessionCard(session: SessionRecord) {
    val statusColor = when (session.sessionStatus) {
        SessionStatus.Running -> PulseSuccess
        SessionStatus.Idle -> PulseWarning
        SessionStatus.Failed -> PulseError
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(session.name.ifBlank { session.provider }, style = MaterialTheme.typography.titleSmall)
                    Text(session.project.ifBlank { "—" }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                StatusBadge(session.status, statusColor)
            }
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Usage: ${formatUsage(session.totalUsage)}", style = MaterialTheme.typography.bodySmall)
                Text("Cost: ${formatCost(session.estimatedCost)}", style = MaterialTheme.typography.bodySmall)
                Text("Req: ${session.requests}", style = MaterialTheme.typography.bodySmall)
            }
            if (session.deviceName.isNotBlank()) {
                Spacer(Modifier.height(4.dp))
                Text("Device: ${session.deviceName}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
