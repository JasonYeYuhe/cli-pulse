// Supabase Edge Function: send-webhook
// Sends alert notifications to user-configured webhook URLs.
// Supports Discord and Slack incoming webhook formats.
//
// Request:
//   { "user_id": "uuid", "alert": { "type", "severity", "title", "message" } }
//
// SSRF Protection:
//   - HTTPS only
//   - Rejects private/loopback/link-local IPs
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
      .select("webhook_url, webhook_enabled")
      .eq("user_id", user_id)
      .single();

    if (fetchError || !settings?.webhook_enabled || !settings?.webhook_url) {
      return new Response(JSON.stringify({ skipped: true, reason: "webhook not configured" }), { status: 200 });
    }

    // Validate URL
    const validation = validateWebhookUrl(settings.webhook_url);
    if (!validation.valid) {
      return new Response(JSON.stringify({ error: validation.error }), { status: 400 });
    }

    // Build Discord-compatible payload (also works with Slack incoming webhooks)
    const color = SEVERITY_COLORS[alert.severity] || 0x95a5a6;
    const payload = {
      content: null,
      embeds: [
        {
          title: `CLI Pulse: ${alert.severity}`,
          description: alert.title,
          color,
          fields: [
            { name: "Type", value: alert.type || "Alert", inline: true },
            { name: "Severity", value: alert.severity || "Info", inline: true },
          ],
          footer: { text: "CLI Pulse Alert" },
          timestamp: new Date().toISOString(),
        },
      ],
    };

    if (alert.message) {
      payload.embeds[0].fields.push({ name: "Details", value: alert.message.substring(0, 1024), inline: false });
    }
    if (alert.related_provider) {
      payload.embeds[0].fields.push({ name: "Provider", value: alert.related_provider, inline: true });
    }

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
