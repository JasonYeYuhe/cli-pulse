// Supabase Edge Function: validate-receipt
// Validates StoreKit 2 JWS signed transactions using Apple's official library
// and updates user tier with anti-replay protection.
//
// Required env vars (auto-injected by Supabase):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Required secrets (set via `supabase secrets set`):
//   APPLE_APP_APPLE_ID  — numeric App Apple ID from App Store Connect
//
// Expected request body:
//   { "transactionJWS": "<JWS string>", "productId": "<product ID>" }
//
// Returns:
//   { "verified": true/false, "tier": "free"|"pro"|"team" }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  SignedDataVerifier,
  Environment,
} from "npm:@apple/app-store-server-library@3";

// Apple Root CA certificates (G3) — required by SignedDataVerifier.
// Sourced from https://www.apple.com/certificateauthority/
const APPLE_ROOT_CA_G3_PEM = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKR1FEZFarRCfFo5q05fw2AYI2cB
X8c0UNJudXLspZuldDANMQswCQYDVQQGEwJVUzEfMB0GA1UEChMWQXBwbGUgVHJ1
c3QgU2VydmljZXMxEzARBgNVBAMTCkFwcGxlIFJvb3QwCgYIKoZIzj0EAwMDaAAw
ZQIxAI1s3R3Z5fM9WQLO3hKj3FZFHsjLK09N2Jn4tVuKasMI1BWLHiTZsE+MALKF
mlxXhwIwIZeCPj14eRbl/dCGMuDLN3seYJPSdaEaIG+oVJx1WnGZim0b3dIkIvPs
p0bfGNeVhU6v
-----END CERTIFICATE-----`;

const EXPECTED_BUNDLE_ID = "yyh.CLI-Pulse";

// Product ID → tier mapping
const PRODUCT_TIER_MAP: Record<string, string> = {
  "com.clipulse.pro.monthly": "pro",
  "com.clipulse.pro.yearly": "pro",
  "com.clipulse.team.monthly": "team",
  "com.clipulse.team.yearly": "team",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    // ── Authenticate caller via Supabase JWT ──
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return jsonResponse({ error: "Missing authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const appAppleId = Number(
      Deno.env.get("APPLE_APP_APPLE_ID") ?? "0",
    );

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    // ── Parse request body ──
    const body = await req.json();
    const { transactionJWS, productId } = body as {
      transactionJWS: string;
      productId: string;
    };
    if (!transactionJWS || !productId) {
      return jsonResponse(
        { error: "Missing transactionJWS or productId" },
        400,
      );
    }

    // ── Verify JWS using Apple's official library ──
    // SignedDataVerifier handles:
    //   - Full x5c certificate chain cryptographic verification
    //   - Signature verification (ES256)
    //   - Environment validation (Production vs Sandbox)
    //   - Bundle ID validation
    const rootCerts = [
      new TextEncoder().encode(APPLE_ROOT_CA_G3_PEM).buffer,
    ];
    const verifier = new SignedDataVerifier(
      rootCerts,
      true, // enableOnlineChecks (OCSP)
      Environment.PRODUCTION,
      EXPECTED_BUNDLE_ID,
      appAppleId,
    );

    let payload;
    try {
      payload = await verifier.verifyAndDecodeTransaction(transactionJWS);
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "JWS verification failed";
      return jsonResponse({ verified: false, error: message }, 400);
    }

    // ── Validate product ID matches client claim ──
    if (payload.productId !== productId) {
      return jsonResponse(
        { verified: false, error: "Product ID mismatch" },
        400,
      );
    }

    // ── Check expiration ──
    if (payload.expiresDate) {
      if (payload.expiresDate < Date.now()) {
        return jsonResponse(
          { verified: false, error: "Subscription expired", tier: "free" },
          200,
        );
      }
    }

    // ── Anti-replay: ensure transaction not owned by another user ──
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    const { data: existingSub } = await adminClient
      .from("subscriptions")
      .select("user_id")
      .eq(
        "apple_original_transaction_id",
        payload.originalTransactionId,
      )
      .maybeSingle();

    if (existingSub && existingSub.user_id !== user.id) {
      return jsonResponse(
        {
          verified: false,
          error: "Transaction already associated with another account",
        },
        403,
      );
    }

    // ── Map product → tier ──
    const tier = PRODUCT_TIER_MAP[payload.productId] ?? "free";

    // ── Update profiles.tier (service role bypasses RLS) ──
    const { error: profileError } = await adminClient
      .from("profiles")
      .update({
        tier,
        receipt_verified_at: new Date().toISOString(),
        last_transaction_id: String(payload.transactionId),
      })
      .eq("id", user.id);

    if (profileError) {
      console.error("Profile update error:", profileError);
      return jsonResponse(
        { verified: false, error: "Failed to update profile" },
        500,
      );
    }

    // ── Upsert subscriptions record ──
    const { error: subError } = await adminClient
      .from("subscriptions")
      .upsert(
        {
          user_id: user.id,
          tier,
          status: "active",
          current_period_end: payload.expiresDate
            ? new Date(payload.expiresDate).toISOString()
            : null,
          apple_transaction_id: String(payload.transactionId),
          apple_original_transaction_id: String(
            payload.originalTransactionId,
          ),
          apple_product_id: payload.productId,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" },
      );

    if (subError) {
      console.error("Subscription upsert error:", subError);
      // Non-fatal: profile tier already updated
    }

    return jsonResponse({ verified: true, tier });
  } catch (err) {
    console.error("validate-receipt error:", err);
    const message = err instanceof Error ? err.message : "Internal error";
    return jsonResponse({ verified: false, error: message }, 500);
  }
});
