// Supabase Edge Function: send-webhook
// Sends alert notifications to user-configured webhook URLs.
// Auto-detects Discord vs Slack webhook format.
//
// Request:
//   { "user_id": "uuid", "alert": { "type", "severity", "title", "message", "related_provider?" } }
//
// Features:
//   - Slack Block Kit format for hooks.slack.com URLs
//   - Discord embed format for discord.com/api/webhooks URLs
//   - Event filtering via user_settings.webhook_event_filter (JSON)
//   - SSRF protection (HTTPS only, rejects private/loopback IPs)
//   - 60-second deduplication per alert grouping_key

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const DEDUP_WINDOW_MS = 60_000;

function isPrivateIP(hostname: string): boolean {
  // Reject common private/reserved ranges
  const patterns = [
    /^127\./,
    /^10\./,
    /^172\.(1[6-9]|2\d|3[01])\./,
    /^192\.168\./,
    /^169\.254\./,
    /^0\./,
    /^localhost$/i,
    /^::1$/,
    /^fc00:/i,
    /^fe80:/i,
    /^fd/i,
    /^::ffff:/i,       // IPv4-mapped IPv6 bypass
    /^\[::ffff:/i,     // Bracketed form
    /^0\.0\.0\.0$/,
  ];
  return patterns.some((p) => p.test(hostname));
}

function validateWebhookUrl(url: string): { valid: boolean; error?: string } {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:") {
      return { valid: false, error: "Only HTTPS webhook URLs are allowed" };
    }
    if (isPrivateIP(parsed.hostname)) {
      return { valid: false, error: "Webhook URL must not point to private/internal addresses" };
    }
    return { valid: true };
  } catch {
    return { valid: false, error: "Invalid webhook URL" };
  }
}

const SEVERITY_COLORS: Record<string, number> = {
  Critical: 0xff0000,
  Warning: 0xffa500,
  Info: 0x3498db,
};

const SEVERITY_EMOJI: Record<string, string> = {
  Critical: "\u{1F6A8}",
  Warning: "\u26A0\uFE0F",
  Info: "\u2139\uFE0F",
};

function isSlackUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.hostname === "hooks.slack.com";
  } catch {
    return false;
  }
}

interface WebhookEventFilter {
  severities?: string[];   // e.g. ["Critical", "Warning"]
  types?: string[];        // e.g. ["cost_spike", "quota_exceeded"]
  providers?: string[];    // e.g. ["Claude", "OpenRouter"]
}

function shouldSendAlert(
  alert: { type?: string; severity?: string; related_provider?: string },
  filter: WebhookEventFilter | null,
): boolean {
  if (!filter) return true;
  if (filter.severities?.length && !filter.severities.includes(alert.severity || "Info")) {
    return false;
  }
  if (filter.types?.length && !filter.types.includes(alert.type || "")) {
    return false;
  }
  if (filter.providers?.length && alert.related_provider && !filter.providers.includes(alert.related_provider)) {
    return false;
  }
  return true;
}

function buildSlackPayload(alert: {
  type?: string;
  severity?: string;
  title?: string;
  message?: string;
  related_provider?: string;
}): Record<string, unknown> {
  const emoji = SEVERITY_EMOJI[alert.severity || "Info"] || "\u2139\uFE0F";
  const blocks: Record<string, unknown>[] = [
    {
      type: "header",
      text: { type: "plain_text", text: `${emoji} CLI Pulse: ${alert.severity || "Info"}`, emoji: true },
    },
    {
      type: "section",
      text: { type: "mrkdwn", text: `*${alert.title || "Alert"}*` },
    },
  ];

  const fields: { type: string; text: string }[] = [];
  if (alert.type) fields.push({ type: "mrkdwn", text: `*Type:* ${alert.type}` });
  if (alert.severity) fields.push({ type: "mrkdwn", text: `*Severity:* ${alert.severity}` });
  if (alert.related_provider) fields.push({ type: "mrkdwn", text: `*Provider:* ${alert.related_provider}` });

  if (fields.length > 0) {
    blocks.push({ type: "section", fields });
  }

  if (alert.message) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: alert.message.substring(0, 3000) },
    });
  }

  blocks.push({
    type: "context",
    elements: [
      { type: "mrkdwn", text: `CLI Pulse \u2022 ${new Date().toISOString()}` },
    ],
  });

  return { blocks };
}

function buildDiscordPayload(alert: {
  type?: string;
  severity?: string;
  title?: string;
  message?: string;
  related_provider?: string;
}): Record<string, unknown> {
  const color = SEVERITY_COLORS[alert.severity || "Info"] || 0x95a5a6;
  const fields: { name: string; value: string; inline: boolean }[] = [
    { name: "Type", value: alert.type || "Alert", inline: true },
    { name: "Severity", value: alert.severity || "Info", inline: true },
  ];
  if (alert.message) {
    fields.push({ name: "Details", value: alert.message.substring(0, 1024), inline: false });
  }
  if (alert.related_provider) {
    fields.push({ name: "Provider", value: alert.related_provider, inline: true });
  }

  return {
    content: null,
    embeds: [
      {
        title: `CLI Pulse: ${alert.severity || "Info"}`,
        description: alert.title || "Alert",
        color,
        fields,
        footer: { text: "CLI Pulse Alert" },
        timestamp: new Date().toISOString(),
      },
    ],
  };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type" },
    });
  }

  try {
    // ── Authenticate caller via Supabase JWT ──
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization header" }), { status: 401 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    // ── Request size guard ──
    const contentLength = req.headers.get("content-length");
    if (contentLength && parseInt(contentLength) > 102400) {
      return new Response(JSON.stringify({ error: "Request too large" }), { status: 413 });
    }

    const { user_id, alert } = await req.json();
    if (!user_id || !alert) {
      return new Response(JSON.stringify({ error: "Missing user_id or alert" }), { status: 400 });
    }

    // Verify user_id matches authenticated user
    if (user_id !== user.id) {
      return new Response(JSON.stringify({ error: "Forbidden: user_id mismatch" }), { status: 403 });
    }

    // ── Database-backed deduplication ──
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const dedupKey = `webhook:${user_id}:${alert.grouping_key || alert.type}`;
    const { data: recentAlert } = await supabase
      .from("alerts")
      .select("created_at")
      .eq("user_id", user_id)
      .eq("suppression_key", dedupKey)
      .gte("created_at", new Date(Date.now() - DEDUP_WINDOW_MS).toISOString())
      .limit(1)
      .maybeSingle();

    if (recentAlert) {
      return new Response(JSON.stringify({ skipped: true, reason: "dedup" }), { status: 200 });
    }

    const { data: settings, error: fetchError } = await supabase
      .from("user_settings")
      .select("webhook_url, webhook_enabled, webhook_event_filter")
      .eq("user_id", user_id)
      .single();

    if (fetchError || !settings?.webhook_enabled || !settings?.webhook_url) {
      return new Response(JSON.stringify({ skipped: true, reason: "webhook not configured" }), { status: 200 });
    }

    // Apply event filter (if configured)
    const eventFilter: WebhookEventFilter | null = settings.webhook_event_filter || null;
    if (!shouldSendAlert(alert, eventFilter)) {
      return new Response(JSON.stringify({ skipped: true, reason: "filtered" }), { status: 200 });
    }

    // Validate URL
    const validation = validateWebhookUrl(settings.webhook_url);
    if (!validation.valid) {
      return new Response(JSON.stringify({ error: validation.error }), { status: 400 });
    }

    // Build payload — auto-detect Slack vs Discord format
    const payload = isSlackUrl(settings.webhook_url)
      ? buildSlackPayload(alert)
      : buildDiscordPayload(alert);

    // Send webhook (5s timeout to prevent tarpit attacks)
    const webhookResp = await fetch(settings.webhook_url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(5000),
    });

    if (!webhookResp.ok) {
      const body = await webhookResp.text().catch(() => "");
      return new Response(
        JSON.stringify({ sent: false, status: webhookResp.status, body: body.substring(0, 200) }),
        { status: 502 },
      );
    }

    return new Response(JSON.stringify({ sent: true }), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
