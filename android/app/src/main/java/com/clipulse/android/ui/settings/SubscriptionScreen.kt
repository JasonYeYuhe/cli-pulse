package com.clipulse.android.ui.settings

import android.app.Activity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.android.billingclient.api.ProductDetails

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionScreen(
    viewModel: SubscriptionViewModel = hiltViewModel(),
    onBack: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val activity = context as? Activity

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Subscription") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            // Current tier
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = when (state.tier) {
                        "team" -> MaterialTheme.colorScheme.primaryContainer
                        "pro" -> MaterialTheme.colorScheme.secondaryContainer
                        else -> MaterialTheme.colorScheme.surfaceVariant
                    },
                ),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "Current Plan: ${state.tier.replaceFirstChar { it.uppercase() }}",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    if (state.isPending) {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "Payment processing...",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.tertiary,
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Feature comparison
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Plan Features", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(12.dp))
                    FeatureRow("Providers", "3", "Unlimited", "Unlimited")
                    FeatureRow("Devices", "1", "5", "Unlimited")
                    FeatureRow("Data Retention", "7 days", "90 days", "365 days")
                }
            }

            Spacer(Modifier.height(16.dp))

            // Available products
            if (state.products.isNotEmpty()) {
                Text(
                    "Available Plans",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
                state.products.forEach { product ->
                    ProductCard(
                        product = product,
                        currentTier = state.tier,
                        onPurchase = { activity?.let { viewModel.purchase(it, product) } },
                    )
                    Spacer(Modifier.height(8.dp))
                }
            } else if (state.isLoading) {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            Spacer(Modifier.height(16.dp))

            // Restore
            OutlinedButton(
                onClick = { viewModel.restore() },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.Refresh, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Restore Purchases")
            }
        }
    }
}

@Composable
private fun FeatureRow(label: String, free: String, pro: String, team: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
        Text(free, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
        Text(pro, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
        Text(team, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun ProductCard(
    product: ProductDetails,
    currentTier: String,
    onPurchase: () -> Unit,
) {
    val offer = product.subscriptionOfferDetails?.firstOrNull()
    val price = offer?.pricingPhases?.pricingPhaseList?.firstOrNull()?.formattedPrice ?: ""
    val period = offer?.pricingPhases?.pricingPhaseList?.firstOrNull()?.billingPeriod ?: ""
    val periodLabel = when {
        period.contains("Y") -> "/year"
        period.contains("M") -> "/month"
        else -> ""
    }

    val productTier = when {
        product.productId.contains("team") -> "team"
        product.productId.contains("pro") -> "pro"
        else -> "free"
    }
    val isCurrentPlan = productTier == currentTier

    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    product.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    "$price$periodLabel",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            if (isCurrentPlan) {
                AssistChip(
                    onClick = {},
                    label = { Text("Current") },
                    leadingIcon = { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(16.dp)) },
                )
            } else {
                Button(onClick = onPurchase) {
                    Text("Subscribe")
                }
            }
        }
    }
}
