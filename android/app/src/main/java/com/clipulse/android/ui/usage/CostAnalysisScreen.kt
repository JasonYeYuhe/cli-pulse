package com.clipulse.android.ui.usage

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.R
import com.clipulse.android.ui.navigation.LocalSnackbarHostState
import com.clipulse.android.ui.theme.providerColor

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CostAnalysisScreen(
    viewModel: DailyUsageViewModel = hiltViewModel(),
    onBack: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val snackbar = LocalSnackbarHostState.current
    var selectedTab by remember { mutableIntStateOf(0) }
    LaunchedEffect(state.error) {
        state.error?.let { snackbar.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.cost_analysis_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
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
            // Time range tabs
            TabRow(selectedTabIndex = selectedTab) {
                Tab(selected = selectedTab == 0, onClick = { selectedTab = 0; viewModel.refresh(7) }) {
                    Text(stringResource(R.string.cost_7_days), modifier = Modifier.padding(12.dp))
                }
                Tab(selected = selectedTab == 1, onClick = { selectedTab = 1; viewModel.refresh(14) }) {
                    Text(stringResource(R.string.cost_14_days), modifier = Modifier.padding(12.dp))
                }
                Tab(selected = selectedTab == 2, onClick = { selectedTab = 2; viewModel.refresh(30) }) {
                    Text(stringResource(R.string.cost_30_days), modifier = Modifier.padding(12.dp))
                }
            }

            Spacer(Modifier.height(16.dp))

            if (state.isLoading) {
                Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else if (state.dailyUsage.isEmpty()) {
                Text(
                    stringResource(R.string.cost_no_data),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(32.dp),
                )
            } else {
                // Cost by Provider
                val costByProvider = viewModel.costByProvider().entries.sortedByDescending { it.value }
                if (costByProvider.isNotEmpty()) {
                    Text(
                        stringResource(R.string.cost_by_provider),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(8.dp))
                    HorizontalBarChart(
                        items = costByProvider.take(8).map { BarItem(it.key, it.value, providerColor(it.key)) },
                    )
                }

                Spacer(Modifier.height(24.dp))

                // Cost by Model
                val costByModel = viewModel.costByModel().entries.sortedByDescending { it.value }
                if (costByModel.isNotEmpty()) {
                    Text(
                        stringResource(R.string.cost_by_model),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(8.dp))
                    HorizontalBarChart(
                        items = costByModel.take(10).map { BarItem(it.key, it.value, MaterialTheme.colorScheme.primary) },
                    )
                }

                Spacer(Modifier.height(24.dp))

                // Daily cost trend
                val costByDate = viewModel.costByDate()
                if (costByDate.isNotEmpty()) {
                    Text(
                        stringResource(R.string.cost_daily_trend),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(8.dp))
                    DailyCostBars(costByDate)
                }
            }
        }
    }
}

data class BarItem(val label: String, val value: Double, val color: Color)

@Composable
private fun HorizontalBarChart(items: List<BarItem>) {
    val maxValue = items.maxOfOrNull { it.value } ?: 1.0
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (item in items) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    item.label,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.width(100.dp),
                )
                Spacer(Modifier.width(8.dp))
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(16.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(item.color.copy(alpha = 0.1f)),
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxHeight()
                            .fillMaxWidth(fraction = if (maxValue > 0) (item.value / maxValue).toFloat() else 0f)
                            .clip(RoundedCornerShape(4.dp))
                            .background(item.color.copy(alpha = 0.7f)),
                    )
                }
                Spacer(Modifier.width(8.dp))
                Text(
                    formatCostCompact(item.value),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.width(55.dp),
                )
            }
        }
    }
}

@Composable
private fun DailyCostBars(costByDate: Map<String, Double>) {
    val entries = costByDate.entries.toList()
    val maxCost = entries.maxOfOrNull { it.value } ?: 1.0

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(80.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        for ((_, cost) in entries) {
            val fraction = if (maxCost > 0) (cost / maxCost).toFloat() else 0f
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(fraction = fraction.coerceAtLeast(0.02f))
                    .clip(RoundedCornerShape(topStart = 2.dp, topEnd = 2.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.6f)),
            )
        }
    }

    // Date labels (first and last)
    if (entries.size >= 2) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(
                entries.first().key.takeLast(5),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.weight(1f))
            Text(
                entries.last().key.takeLast(5),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun formatCostCompact(cost: Double): String {
    if (cost < 0.01) return "<$0.01"
    if (cost < 1.0) return String.format("$%.2f", cost)
    return String.format("$%.1f", cost)
}
