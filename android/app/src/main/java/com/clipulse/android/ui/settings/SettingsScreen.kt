package com.clipulse.android.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onSignOut: () -> Unit,
    onManageSubscription: () -> Unit = {},
    onViewDevices: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(16.dp))

        // Account info
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("Account", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                if (state.userName != null) {
                    Text(state.userName!!, style = MaterialTheme.typography.bodyMedium)
                }
                if (state.userEmail != null) {
                    Text(state.userEmail!!, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.height(8.dp))
                Text("Tier: ${state.tier}", style = MaterialTheme.typography.labelMedium)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = onManageSubscription, modifier = Modifier.weight(1f)) {
                        Text("Subscription")
                    }
                    OutlinedButton(onClick = onViewDevices, modifier = Modifier.weight(1f)) {
                        Text("Devices")
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))

        // Settings from server (editable)
        val settings = state.settings
        if (settings != null) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Notifications", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Enabled", modifier = Modifier.weight(1f))
                        Switch(
                            checked = settings.notificationsEnabled,
                            onCheckedChange = { viewModel.updateSetting("notifications_enabled", it) },
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Thresholds", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))

                    EditableSettingRow("Usage Spike (tokens)", settings.usageSpikeThreshold) {
                        viewModel.updateSetting("usage_spike_threshold", it)
                    }
                    EditableSettingRow("Project Budget ($)", settings.projectBudgetThresholdUsd.toInt()) {
                        viewModel.updateSetting("project_budget_threshold_usd", it.toDouble() / 100.0 * 100.0)
                    }
                    EditableSettingRow("Long Session (min)", settings.sessionTooLongThresholdMinutes) {
                        viewModel.updateSetting("session_too_long_threshold_minutes", it)
                    }
                    EditableSettingRow("Offline Grace (min)", settings.offlineGracePeriodMinutes) {
                        viewModel.updateSetting("offline_grace_period_minutes", it)
                    }
                    EditableSettingRow("Data Retention (days)", settings.dataRetentionDays) {
                        viewModel.updateSetting("data_retention_days", maxOf(1, it))
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        // Sign out
        OutlinedButton(
            onClick = {
                viewModel.signOut()
                onSignOut()
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text("Sign Out")
        }

        Spacer(Modifier.height(12.dp))

        state.deleteError?.let { error ->
            Spacer(Modifier.height(8.dp))
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(error, modifier = Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onErrorContainer)
            }
        }

        // Delete account
        var showDeleteConfirm by remember { mutableStateOf(false) }
        TextButton(
            onClick = { showDeleteConfirm = true },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
        ) {
            Text("Delete Account")
        }

        if (showDeleteConfirm) {
            AlertDialog(
                onDismissRequest = { showDeleteConfirm = false },
                title = { Text("Delete Account?") },
                text = { Text("This will permanently delete all your data. This action cannot be undone.") },
                confirmButton = {
                    TextButton(
                        onClick = {
                            showDeleteConfirm = false
                            viewModel.deleteAccount(onSuccess = onSignOut)
                        },
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) {
                        Text("Delete")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showDeleteConfirm = false }) {
                        Text("Cancel")
                    }
                },
            )
        }
    }
}

@Composable
private fun EditableSettingRow(label: String, currentValue: Int, onUpdate: (Int) -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var textValue by remember(currentValue) { mutableStateOf(currentValue.toString()) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        if (editing) {
            OutlinedTextField(
                value = textValue,
                onValueChange = { textValue = it.filter { c -> c.isDigit() } },
                modifier = Modifier.width(100.dp),
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium,
            )
            IconButton(onClick = {
                editing = false
                textValue.toIntOrNull()?.let { onUpdate(it) }
            }) {
                Icon(Icons.Filled.Check, contentDescription = "Save")
            }
        } else {
            TextButton(onClick = { editing = true }) {
                Text(currentValue.toString())
            }
        }
    }
}
