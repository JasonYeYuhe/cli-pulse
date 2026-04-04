// Supabase Edge Function: validate-receipt
// Validates subscription receipts from Apple (StoreKit 2 JWS) and Google Play.
// Unified endpoint — `platform` field determines the verification path.
//
// Required env vars (auto-injected by Supabase):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Required secrets:
//   APPLE_APP_APPLE_ID — numeric App Apple ID from App Store Connect
//   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON — Google Cloud service account key JSON
//
// Apple request:
//   { "platform": "apple", "transactionJWS": "...", "productId": "..." }
// Google request:
//   { "platform": "google", "purchaseToken": "...", "productId": "...", "packageName": "..." }
//
// Returns:
//   { "verified": true/false, "tier": "free"|"pro"|"team" }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  SignedDataVerifier,
  Environment,
} from "npm:@apple/app-store-server-library@3";

// Apple Root CA G3 — required by SignedDataVerifier
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

const APPLE_BUNDLE_ID = "yyh.CLI-Pulse";
const GOOGLE_PACKAGE_NAME = "com.clipulse.android";

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

// ── Google Play verification helpers ──

interface GoogleTokenPayload {
  iss: string;
  scope: string;
  aud: string;
  exp: number;
  iat: number;
}

async function getGoogleAccessToken(
  serviceAccountJson: string,
): Promise<string> {
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);

  // Build JWT header + payload
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

  const signingInput = `${enc(header)}.${enc(payload)}`;

  // Import RSA private key
  const pemBody = sa.private_key
    .replace(/-----[^-]+-----/g, "")
    .replace(/\s/g, "");
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${signingInput}.${sigB64}`;

  // Exchange JWT for access token
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`Google OAuth failed: ${errText}`);
  }

  const tokenResp = await resp.json();
  return tokenResp.access_token;
}

async function verifyGooglePurchase(
  packageName: string,
  productId: string,
  purchaseToken: string,
  accessToken: string,
): Promise<{
  valid: boolean;
  orderId?: string;
  expiryTime?: string;
  error?: string;
}> {
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptionsv2/tokens/${purchaseToken}`;

  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!resp.ok) {
    const errText = await resp.text();
    return { valid: false, error: `Google API error: ${resp.status} ${errText}` };
  }

  const data = await resp.json();

  // Check subscription state
  const state = data.subscriptionState;
  if (
    state !== "SUBSCRIPTION_STATE_ACTIVE" &&
    state !== "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
  ) {
    return {
      valid: false,
      error: `Subscription not active: ${state}`,
    };
  }

  // Verify the line item matches the expected product
  const lineItems = data.lineItems || [];
  const matchingItem = lineItems.find(
    (item: { productId: string }) => item.productId === productId,
  );
  if (!matchingItem) {
    return { valid: false, error: "Product ID not found in subscription" };
  }

  const expiryTime = matchingItem.expiryTime;
  const latestOrderId = data.latestOrderId;

  return {
    valid: true,
    orderId: latestOrderId,
    expiryTime,
  };
}

// ── Main handler ──

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
    const platform: string = body.platform ?? "apple";
    const productId: string = body.productId ?? "";

    if (!productId) {
      return jsonResponse({ error: "Missing productId" }, 400);
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceKey);
    let tier: string;
    let transactionId: string;
    let expiresDate: string | null = null;
    let originalTransactionId: string | null = null;
    let playOrderId: string | null = null;

    if (platform === "apple") {
      // ── Apple StoreKit 2 JWS verification ──
      const transactionJWS: string = body.transactionJWS ?? "";
      if (!transactionJWS) {
        return jsonResponse({ error: "Missing transactionJWS" }, 400);
      }

      const appAppleId = Number(Deno.env.get("APPLE_APP_APPLE_ID") ?? "0");
      const rootCerts = [
        new TextEncoder().encode(APPLE_ROOT_CA_G3_PEM).buffer,
      ];
      const verifier = new SignedDataVerifier(
        rootCerts,
        true,
        Environment.PRODUCTION,
        APPLE_BUNDLE_ID,
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

      if (payload.productId !== productId) {
        return jsonResponse(
          { verified: false, error: "Product ID mismatch" },
          400,
        );
      }

      if (payload.expiresDate && payload.expiresDate < Date.now()) {
        return jsonResponse(
          { verified: false, error: "Subscription expired", tier: "free" },
          200,
        );
      }

      // Anti-replay for Apple
      const { data: existingSub } = await adminClient
        .from("subscriptions")
        .select("user_id")
        .eq("apple_original_transaction_id", payload.originalTransactionId)
        .neq("user_id", user.id)
        .maybeSingle();

      if (existingSub) {
        return jsonResponse(
          {
            verified: false,
            error: "Transaction already associated with another account",
          },
          403,
        );
      }

      tier = PRODUCT_TIER_MAP[payload.productId] ?? "free";
      transactionId = String(payload.transactionId);
      originalTransactionId = String(payload.originalTransactionId);
      expiresDate = payload.expiresDate
        ? new Date(payload.expiresDate).toISOString()
        : null;
    } else if (platform === "google") {
      // ── Google Play verification ──
      const purchaseToken: string = body.purchaseToken ?? "";
      const packageName: string = body.packageName ?? GOOGLE_PACKAGE_NAME;

      if (!purchaseToken) {
        return jsonResponse({ error: "Missing purchaseToken" }, 400);
      }

      if (packageName !== GOOGLE_PACKAGE_NAME) {
        return jsonResponse(
          { verified: false, error: "Package name mismatch" },
          400,
        );
      }

      const saJson = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
      if (!saJson) {
        return jsonResponse(
          { verified: false, error: "Google Play verification not configured" },
          500,
        );
      }

      const accessToken = await getGoogleAccessToken(saJson);
      const result = await verifyGooglePurchase(
        packageName,
        productId,
        purchaseToken,
        accessToken,
      );

      if (!result.valid) {
        return jsonResponse(
          { verified: false, error: result.error ?? "Verification failed" },
          400,
        );
      }

      // Anti-replay for Google
      if (result.orderId) {
        const { data: existingSub } = await adminClient
          .from("subscriptions")
          .select("user_id")
          .eq("play_order_id", result.orderId)
          .neq("user_id", user.id)
          .maybeSingle();

        if (existingSub) {
          return jsonResponse(
            {
              verified: false,
              error: "Purchase already associated with another account",
            },
            403,
          );
        }
      }

      tier = PRODUCT_TIER_MAP[productId] ?? "free";
      transactionId = result.orderId ?? purchaseToken.slice(0, 64);
      playOrderId = result.orderId ?? null;
      expiresDate = result.expiryTime ?? null;
    } else {
      return jsonResponse({ error: `Unknown platform: ${platform}` }, 400);
    }

    // ── Update profiles.tier ──
    const { error: profileError } = await adminClient
      .from("profiles")
      .update({
        tier,
        receipt_verified_at: new Date().toISOString(),
        last_transaction_id: transactionId,
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
    const subRecord: Record<string, unknown> = {
      user_id: user.id,
      tier,
      status: "active",
      platform,
      current_period_end: expiresDate,
      apple_product_id: productId,
      updated_at: new Date().toISOString(),
    };
    if (platform === "apple") {
      subRecord.apple_transaction_id = transactionId;
      subRecord.apple_original_transaction_id = originalTransactionId;
    } else if (platform === "google") {
      subRecord.play_order_id = playOrderId;
    }

    const { error: subError } = await adminClient
      .from("subscriptions")
      .upsert(subRecord, { onConflict: "user_id" });

    if (subError) {
      console.error("Subscription upsert error:", subError);
    }

    return jsonResponse({ verified: true, tier });
  } catch (err) {
    console.error("validate-receipt error:", err);
    const message = err instanceof Error ? err.message : "Internal error";
    return jsonResponse({ verified: false, error: message }, 500);
  }
});
