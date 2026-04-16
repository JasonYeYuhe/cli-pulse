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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.R

@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onSignOut: () -> Unit,
    onManageSubscription: () -> Unit = {},
    onViewDevices: () -> Unit = {},
    onViewTeams: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text(stringResource(R.string.tab_settings), style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(16.dp))

        // Account info
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(stringResource(R.string.settings_account), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                state.userName?.let { name ->
                    Text(name, style = MaterialTheme.typography.bodyMedium)
                }
                state.userEmail?.let { email ->
                    Text(email, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.settings_tier, state.tier), style = MaterialTheme.typography.labelMedium)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = onManageSubscription, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.settings_subscription))
                    }
                    OutlinedButton(onClick = onViewDevices, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.settings_devices))
                    }
                }
                Spacer(Modifier.height(4.dp))
                OutlinedButton(onClick = onViewTeams, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.settings_teams))
                }
            }
        }

        Spacer(Modifier.height(16.dp))

        // Settings from server (editable)
        val settings = state.settings
        if (settings != null) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(stringResource(R.string.settings_notifications), style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(stringResource(R.string.settings_enabled), modifier = Modifier.weight(1f))
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
                    Text(stringResource(R.string.settings_thresholds), style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))

                    EditableSettingRow("Usage Spike (tokens)", settings.usageSpikeThreshold) {
                        viewModel.updateSetting("usage_spike_threshold", it)
                    }
                    EditableDecimalRow("Project Budget ($)", settings.projectBudgetThresholdUsd) {
                        viewModel.updateSetting("project_budget_threshold_usd", it)
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

        // Integrations (Webhook)
        Spacer(Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(stringResource(R.string.settings_integrations), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(stringResource(R.string.settings_webhook_notifications), modifier = Modifier.weight(1f))
                    Switch(
                        checked = state.webhookEnabled,
                        onCheckedChange = { viewModel.updateSetting("webhook_enabled", it) },
                    )
                }

                if (state.webhookEnabled) {
                    Spacer(Modifier.height(8.dp))
                    var webhookText by remember(state.webhookUrl) { mutableStateOf(state.webhookUrl ?: "") }
                    OutlinedTextField(
                        value = webhookText,
                        onValueChange = { webhookText = it },
                        label = { Text(stringResource(R.string.settings_webhook_url_hint)) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = { viewModel.updateSetting("webhook_url", webhookText) },
                            enabled = webhookText.isNotBlank(),
                        ) { Text(stringResource(R.string.settings_save_url)) }
                        OutlinedButton(
                            onClick = {
                                viewModel.updateSetting("webhook_url", webhookText)
                                viewModel.testWebhook()
                            },
                            enabled = webhookText.isNotBlank(),
                        ) { Text(stringResource(R.string.settings_test)) }
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        // Demo mode exit or Sign out
        if (state.isDemoMode) {
            OutlinedButton(
                onClick = {
                    viewModel.exitDemoMode()
                    onSignOut()
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.tertiary),
            ) {
                Icon(Icons.Filled.ExitToApp, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.settings_exit_demo))
            }
        } else {
            OutlinedButton(
                onClick = {
                    viewModel.signOut()
                    onSignOut()
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.sign_out))
            }
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
            Text(stringResource(R.string.delete_account))
        }

        if (showDeleteConfirm) {
            AlertDialog(
                onDismissRequest = { showDeleteConfirm = false },
                title = { Text(stringResource(R.string.settings_delete_title)) },
                text = { Text(stringResource(R.string.settings_delete_message)) },
                confirmButton = {
                    TextButton(
                        onClick = {
                            showDeleteConfirm = false
                            viewModel.deleteAccount(onSuccess = onSignOut)
                        },
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) {
                        Text(stringResource(R.string.delete))
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showDeleteConfirm = false }) {
                        Text(stringResource(R.string.cancel))
                    }
                },
            )
        }
    }
}

@Composable
private fun EditableDecimalRow(label: String, currentValue: Double, onUpdate: (Double) -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var textValue by remember(currentValue) { mutableStateOf(String.format("%.2f", currentValue)) }

    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        if (editing) {
            OutlinedTextField(
                value = textValue,
                onValueChange = { textValue = it.filter { c -> c.isDigit() || c == '.' } },
                modifier = Modifier.width(100.dp),
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyMedium,
            )
            IconButton(onClick = {
                editing = false
                textValue.toDoubleOrNull()?.let { onUpdate(it) }
            }) { Icon(Icons.Filled.Check, contentDescription = null) }
        } else {
            TextButton(onClick = { editing = true }) {
                Text(String.format("%.2f", currentValue))
            }
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
