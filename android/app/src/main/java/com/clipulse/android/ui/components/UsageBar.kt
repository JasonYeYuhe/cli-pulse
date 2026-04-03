package com.clipulse.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.clipulse.android.ui.theme.PulseError
import com.clipulse.android.ui.theme.PulseSuccess
import com.clipulse.android.ui.theme.PulseWarning

/**
 * Usage bar that shows REMAINING percentage (matching macOS behavior).
 * @param remainingPercent 0.0 = nothing left (red), 1.0 = fully remaining (green)
 */
@Composable
fun UsageBar(
    remainingPercent: Double,
    modifier: Modifier = Modifier,
    label: String? = null,
    trailingText: String? = null,
) {
    val color = when {
        remainingPercent <= 0.10 -> PulseError
        remainingPercent <= 0.30 -> PulseWarning
        else -> PulseSuccess
    }

    Column(modifier = modifier) {
        if (label != null || trailingText != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(label ?: "", style = MaterialTheme.typography.bodySmall)
                Text(
                    trailingText ?: "${(remainingPercent * 100).toInt()}% left",
                    style = MaterialTheme.typography.bodySmall,
                    color = color,
                )
            }
            Spacer(Modifier.height(4.dp))
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(remainingPercent.coerceIn(0.0, 1.0).toFloat())
                    .clip(RoundedCornerShape(4.dp))
                    .background(color),
            )
        }
    }
}

@Composable
fun MetricCard(
    title: String,
    value: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(16.dp),
        horizontalAlignment = Alignment.Start,
    ) {
        Text(
            title,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            value,
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        if (subtitle != null) {
            Spacer(Modifier.height(2.dp))
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun StatusBadge(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = modifier
            .clip(RoundedCornerShape(4.dp))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

fun formatCost(cost: Double): String =
    if (cost < 0.01 && cost > 0) "<\$0.01"
    else "\$${String.format("%.2f", cost)}"

fun formatUsage(tokens: Int): String = when {
    tokens >= 1_000_000 -> "${String.format("%.1f", tokens / 1_000_000.0)}M"
    tokens >= 1_000 -> "${String.format("%.1f", tokens / 1_000.0)}K"
    else -> tokens.toString()
}

/** Format ISO reset_time to human readable "Resets in Xh Ym" */
fun formatResetTime(isoTime: String?): String? {
    if (isoTime.isNullOrBlank()) return null
    return try {
        val resetInstant = java.time.Instant.parse(isoTime)
        val now = java.time.Instant.now()
        val diff = java.time.Duration.between(now, resetInstant)
        if (diff.isNegative) return "Resetting..."
        val hours = diff.toHours()
        val minutes = diff.toMinutes() % 60
        when {
            hours > 0 -> "Resets in ${hours}h ${minutes}m"
            minutes > 0 -> "Resets in ${minutes}m"
            else -> "Resets soon"
        }
    } catch (_: Exception) {
        null
    }
}
