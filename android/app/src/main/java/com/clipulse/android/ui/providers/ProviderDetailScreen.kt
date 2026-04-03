package com.clipulse.android.ui.providers

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.data.model.ProviderUsage
import com.clipulse.android.ui.components.*
import com.clipulse.android.ui.theme.providerColor

/**
 * Navigation entry point — loads the provider from ViewModel state by name.
 */
@Composable
fun ProviderDetailRoute(
    providerName: String,
    onBack: () -> Unit,
    viewModel: ProvidersViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val provider = state.providers.find { it.provider == providerName }
    if (provider != null) {
        ProviderDetailScreen(provider = provider, onBack = onBack)
    } else {
        // Provider not found or still loading — show back button
        LaunchedEffect(Unit) { viewModel.refresh() }
        Box(modifier = Modifier.fillMaxSize()) {
            CircularProgressIndicator(modifier = Modifier.padding(32.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProviderDetailScreen(
    provider: ProviderUsage,
    onBack: () -> Unit,
) {
    val kind = provider.providerKind
    val color = kind?.let { providerColor(it) } ?: MaterialTheme.colorScheme.primary

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(provider.provider) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            // Status + Plan
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Status", style = MaterialTheme.typography.titleMedium)
                        StatusBadge(provider.statusText, color)
                    }
                    if (provider.planType != null) {
                        Spacer(Modifier.height(8.dp))
                        Text("Plan: ${provider.planType}", style = MaterialTheme.typography.bodyMedium)
                    }
                    if (provider.resetTime != null) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "Resets: ${provider.resetTime}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Overall quota
            if (provider.quota != null && provider.quota > 0) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Overall Quota", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(12.dp))
                        val remainPct = (provider.remaining ?: 0).toDouble() / provider.quota
                        UsageBar(
                            remainingPercent = remainPct,
                            label = "${formatUsage(provider.quota - (provider.remaining ?: 0))} used of ${formatUsage(provider.quota)}",
                            trailingText = "${(remainPct * 100).toInt()}% left",
                        )
                        if (provider.remaining != null) {
                            Spacer(Modifier.height(8.dp))
                            Text(
                                "${formatUsage(provider.remaining)} remaining",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }

            // Tiers
            if (provider.tiers.isNotEmpty()) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Quota Tiers", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(12.dp))
                        provider.tiers.forEach { tier ->
                            val remainPct = if (tier.quota > 0) {
                                tier.remaining.toDouble() / tier.quota
                            } else 0.0
                            val resetLabel = formatResetTime(tier.resetTime)
                            val trailing = buildString {
                                append("${(remainPct * 100).toInt()}% left")
                                if (resetLabel != null) append(" · $resetLabel")
                            }
                            UsageBar(
                                remainingPercent = remainPct,
                                label = tier.name,
                                trailingText = trailing,
                            )
                            Spacer(Modifier.height(12.dp))
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }

            // Usage stats
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Usage", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        MetricCard(
                            title = "Today",
                            value = formatUsage(provider.todayUsage),
                            subtitle = formatCost(provider.estimatedCostToday),
                            modifier = Modifier.weight(1f),
                        )
                        Spacer(Modifier.width(12.dp))
                        MetricCard(
                            title = "This Week",
                            value = formatUsage(provider.weekUsage),
                            subtitle = formatCost(provider.estimatedCostWeek),
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}
