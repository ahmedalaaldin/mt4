import { EmailMessage } from "cloudflare:email";

/**
 * EA Backtest Reporter — Cloudflare Worker
 *
 * POST /api/ea-report  { version, screenshot_base64, results }
 *   - Stores the result in KV
 *   - Fetches the all-time top-5 by Total Return %
 *   - Sends an HTML email via Cloudflare Email Workers
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    if (request.method !== "POST" || !url.pathname.endsWith("/ea-report")) {
      return new Response("Not found", { status: 404 });
    }

    try {
      const body = await request.json();
      const { version, screenshot_base64 = "", results = {} } = body;

      if (!version) {
        return Response.json({ error: "version is required" }, { status: 400 });
      }

      // ── Parse numeric metrics from the results strings ──────────────────
      const returnPct   = parseMetric(results["Total Return"],    /^([\d.]+)/);
      const maxDdPct    = parseMetric(results["Max Drawdown"],    /^([\d.]+)/);
      const winRate     = parseMetric(results["Win Rate"],        /^([\d.]+)/);
      const totalTrades = parseMetric(results["Total Trades"],    /^(\d+)/);
      const maxWins     = parseMetric(results["Max Consecutive Wins"],   /^(\d+)/);
      const maxLosses   = parseMetric(results["Max Consecutive Losses"], /^(\d+)/);

      // ── Persist this result + build leaderboard ─────────────────────────
      // All KV work is wrapped so a storage hiccup or a corrupt key can NEVER
      // block the email — sending the report is the job that must not fail.
      let top5 = [];
      try {
        const record = {
          version,
          timestamp: new Date().toISOString(),
          results,
          returnPct,
          maxDdPct,
          winRate,
          totalTrades,
          maxWins,
          maxLosses,
        };
        await env.EA_RESULTS.put(`ea:result:${version}`, JSON.stringify(record));

        // Track the list of all stored versions. parseJsonSafe strips any BOM
        // and tolerates a corrupt value (resets to []) instead of throwing.
        const listJson = await env.EA_RESULTS.get("ea:all_versions");
        const allVersions = parseJsonSafe(listJson, []);
        if (!allVersions.includes(version)) {
          allVersions.push(version);
          await env.EA_RESULTS.put("ea:all_versions", JSON.stringify(allVersions));
        }

        top5 = await getTop5(env, allVersions);
      } catch (kvErr) {
        console.error("KV/leaderboard step failed (email will still send):", kvErr);
      }

      // ── Build & send email (always runs) ────────────────────────────────
      const timestamp = new Date().toISOString().replace("T", " ").slice(0, 19) + " UTC";
      const html = buildEmail(version, results, !!screenshot_base64, top5, timestamp);
      await sendEmail(env, version, html, screenshot_base64 || null);

      return Response.json({ ok: true });

    } catch (err) {
      console.error("ea-report error:", err);
      return Response.json({ ok: false, error: err?.message ?? String(err) }, { status: 500 });
    }
  },
};

// ── Helpers ────────────────────────────────────────────────────────────────

function parseMetric(str, pattern) {
  if (!str) return 0;
  const m = String(str).match(pattern);
  return m ? parseFloat(m[1]) : 0;
}

// Tolerant JSON parse: strips a leading UTF-8 BOM (﻿) and returns the
// fallback instead of throwing on malformed input. A BOM-prefixed value (e.g.
// written by PowerShell's `Set-Content -Encoding utf8`) is otherwise invalid
// JSON and would crash the whole request.
function parseJsonSafe(str, fallback) {
  if (!str) return fallback;
  try {
    return JSON.parse(String(str).replace(/^﻿/, ""));
  } catch {
    return fallback;
  }
}

// UTF-8-safe base64 (btoa alone is Latin1-only and throws on emoji like the
// leaderboard medals). Encode to bytes first, then base64 the byte string.
function toBase64Utf8(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

async function getTop5(env, allVersions) {
  if (!allVersions.length) return [];

  const records = await Promise.all(
    allVersions.map(async (v) => {
      const json = await env.EA_RESULTS.get(`ea:result:${v}`);
      return parseJsonSafe(json, null);
    })
  );

  return records
    .filter(Boolean)
    .sort((a, b) => b.returnPct - a.returnPct)
    .slice(0, 5);
}

async function sendEmail(env, version, html, screenshotB64) {
  const from     = env.FROM_EMAIL ?? "noreply@traderscastle.com";
  const fromName = env.FROM_NAME  ?? "Traders Castle";
  const to       = env.TO_EMAIL   ?? "ahmed.alaaeldin@icloud.com";
  const subject  = `MT4 EA Backtest - Buy & Sell EA ${version}`;
  const boundary = `ea_report_${Date.now()}`;
  const imgCid   = "equitycurve@ea-reporter";

  // Base64-encode the HTML body. The previous code declared the part as
  // quoted-printable but sent raw HTML — strict clients (Apple Mail / iCloud)
  // then mangle the markup (long lines, unescaped '='), which breaks the inline
  // <img> and the layout. Base64 is unambiguous and renders everywhere.
  const htmlB64 = toBase64Utf8(html).match(/.{1,76}/g).join("\r\n");

  let mime;
  if (screenshotB64) {
    // Multipart/related so the inline CID image is shown in the body (not as an
    // attachment) by all mail clients.
    mime = [
      `From: ${fromName} <${from}>`,
      `To: ${to}`,
      `Subject: ${subject}`,
      `MIME-Version: 1.0`,
      `Content-Type: multipart/related; type="text/html"; boundary="${boundary}"`,
      ``,
      `--${boundary}`,
      `Content-Type: text/html; charset=UTF-8`,
      `Content-Transfer-Encoding: base64`,
      ``,
      htmlB64,
      ``,
      `--${boundary}`,
      `Content-Type: image/png`,
      `Content-Transfer-Encoding: base64`,
      `Content-ID: <${imgCid}>`,
      `Content-Disposition: inline; filename="equity-curve.png"`,
      ``,
      // Split base64 into 76-char lines (RFC 2045)
      screenshotB64.match(/.{1,76}/g).join("\r\n"),
      ``,
      `--${boundary}--`,
    ].join("\r\n");
  } else {
    mime = [
      `From: ${fromName} <${from}>`,
      `To: ${to}`,
      `Subject: ${subject}`,
      `MIME-Version: 1.0`,
      `Content-Type: text/html; charset=UTF-8`,
      `Content-Transfer-Encoding: base64`,
      ``,
      htmlB64,
    ].join("\r\n");
  }

  const msg = new EmailMessage(from, to, mime);
  await env.SEND_EMAIL.send(msg);
}

// ── HTML Builder ───────────────────────────────────────────────────────────

function buildEmail(version, results, hasImage, top5, timestamp) {
  const resultRows = Object.entries(results)
    .map(([k, v]) => `
      <tr>
        <td style="padding:8px 12px;color:#6b7280;font-size:14px;border-bottom:1px solid #e5e7eb;white-space:nowrap;">${k}</td>
        <td style="padding:8px 12px;color:#1f2937;font-size:14px;font-weight:600;text-align:right;border-bottom:1px solid #e5e7eb;">${v}</td>
      </tr>`)
    .join("");

  // Use CID reference — the actual image bytes are attached as a MIME part
  const screenshotSection = hasImage ? `
    <tr><td style="padding:0 40px 32px;">
      <p style="color:#1f2937;font-size:14px;font-weight:600;margin:0 0 12px;">Equity Curve</p>
      <img src="cid:equitycurve@ea-reporter"
           alt="Equity Curve"
           style="width:100%;max-width:520px;height:auto;border:1px solid #e5e7eb;border-radius:6px;display:block;" />
    </td></tr>` : "";

  const leaderboardSection = top5.length ? buildLeaderboard(top5, version) : "";

  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>MT4 EA Backtest - Buy &amp; Sell EA ${version}</title></head>
<body style="margin:0;padding:0;background:#f9fafb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f9fafb;">
  <tr><td align="center" style="padding:32px 0;">
    <table role="presentation" width="600" cellspacing="0" cellpadding="0"
           style="background:#ffffff;border-radius:8px;overflow:hidden;max-width:600px;">

      <!-- Header -->
      <tr><td style="padding:32px 40px 24px;background:#1f2937;">
        <p style="margin:0;font-size:12px;color:#9ca3af;text-transform:uppercase;letter-spacing:1px;">MT4 Strategy Tester</p>
        <h1 style="margin:8px 0 0;font-size:22px;font-weight:700;color:#ffffff;">Buy &amp; Sell EA ${version}</h1>
        <p style="margin:8px 0 0;font-size:13px;color:#9ca3af;">${timestamp}</p>
      </td></tr>

      <!-- Results Summary -->
      ${resultRows ? `<tr><td style="padding:24px 40px;">
        <p style="color:#1f2937;font-size:14px;font-weight:600;margin:0 0 12px;">Results Summary</p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0"
               style="border:1px solid #e5e7eb;border-radius:6px;overflow:hidden;">
          ${resultRows}
        </table>
      </td></tr>` : ""}

      <!-- Equity Curve -->
      ${screenshotSection}

      <!-- Top 5 Leaderboard -->
      ${leaderboardSection}

      <!-- Footer -->
      <tr><td style="padding:16px 40px 32px;border-top:1px solid #e5e7eb;">
        <p style="margin:0;font-size:12px;color:#9ca3af;">XAUUSD &bull; Auto-sent from MT4 Strategy Tester</p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>`;
}

function buildLeaderboard(top5, currentVersion) {
  const medal = ["🥇", "🥈", "🥉", "4.", "5."];

  const rows = top5.map((r, i) => {
    const isCurrentVersion = r.version === currentVersion;
    const rowBg = isCurrentVersion ? "#f0fdf4" : (i % 2 === 0 ? "#ffffff" : "#f9fafb");
    const versionLabel = isCurrentVersion
      ? `<strong>v${r.version}</strong> <span style="color:#16a34a;font-size:11px;">← this run</span>`
      : `v${r.version}`;

    return `
      <tr style="background:${rowBg};">
        <td style="padding:9px 10px;font-size:13px;text-align:center;">${medal[i]}</td>
        <td style="padding:9px 10px;font-size:13px;color:#1f2937;">${versionLabel}</td>
        <td style="padding:9px 10px;font-size:13px;font-weight:700;color:#15803d;text-align:right;">+${r.returnPct.toFixed(2)}%</td>
        <td style="padding:9px 10px;font-size:13px;color:#dc2626;text-align:right;">${r.maxDdPct.toFixed(2)}%</td>
        <td style="padding:9px 10px;font-size:13px;color:#6b7280;text-align:right;">${r.winRate.toFixed(1)}%</td>
        <td style="padding:9px 10px;font-size:13px;color:#6b7280;text-align:right;">${r.totalTrades}</td>
        <td style="padding:9px 10px;font-size:13px;color:#dc2626;text-align:right;">${r.maxLosses}</td>
      </tr>`;
  }).join("");

  return `
    <tr><td style="padding:0 40px 32px;">
      <p style="color:#1f2937;font-size:14px;font-weight:600;margin:0 0 12px;">All-Time Top 5 Versions</p>
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0"
             style="border:1px solid #e5e7eb;border-radius:6px;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
        <thead>
          <tr style="background:#f3f4f6;">
            <th style="padding:8px 10px;font-size:11px;color:#6b7280;font-weight:600;text-align:center;">#</th>
            <th style="padding:8px 10px;font-size:11px;color:#6b7280;font-weight:600;text-align:left;">Version</th>
            <th style="padding:8px 10px;font-size:11px;color:#6b7280;font-weight:600;text-align:right;">Return</th>
            <th style="padding:8px 10px;font-size:11px;color:#6b7280;font-weight:600;text-align:right;">Max DD</th>
            <th style="padding:8px 10px;font-size:11px;color:#6b7280;font-weight:600;text-align:right;">Win Rate</th>
            <th style="padding:8px 10px;font-size:11px;color:#6b7280;font-weight:600;text-align:right;">Trades</th>
            <th style="padding:8px 10px;font-size:11px;color:#6b7280;font-weight:600;text-align:right;">Max Losses</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    </td></tr>`;
}
