interface DurableObjectId {}

interface DurableObjectStub {
  fetch(request: Request): Promise<Response>;
}

interface DurableObjectNamespace {
  idFromName(name: string): DurableObjectId;
  get(id: DurableObjectId): DurableObjectStub;
}

interface SqlStorage {
  exec<T = Record<string, unknown>>(query: string, ...bindings: unknown[]): Iterable<T>;
}

interface DurableObjectState {
  storage: { sql: SqlStorage };
}

export interface Env {
  TELEGRAM_BOT_TOKEN: string;
  TELEGRAM_CHAT_ID: string;
  RELAY_API_KEY: string;
  IDEMPOTENCY: DurableObjectNamespace;
  CF_VERSION_METADATA: {
    id: string;
    tag: string;
    timestamp: string;
  };
}

export interface AlertPayload {
  event_id: string;
  event_type: "test" | "low_battery" | "full_charge";
  battery: number;
  charging: boolean;
  message: string;
}

interface DeliveryResult {
  status: number;
  body: {
    ok: boolean;
    delivered?: boolean;
    duplicate?: boolean;
    event_id?: string;
    error?: string;
  };
}

type Fetcher = typeof fetch;

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

const HTML_HEADERS = {
  "content-type": "text/html; charset=UTF-8",
  "cache-control": "public, max-age=3600",
};

const PRIVACY_POLICY_HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Garmin Battery Alert Privacy Policy</title>
  <style>
    body { max-width: 760px; margin: 0 auto; padding: 2rem 1.25rem; color: #202124; background: #fff; font: 16px/1.6 system-ui, sans-serif; }
    h1 { line-height: 1.2; }
    h2 { margin-top: 1.8rem; font-size: 1.25rem; }
  </style>
</head>
<body>
  <main>
    <h1>Garmin Battery Alert Privacy Policy</h1>
    <p><strong>Effective date:</strong> August 18, 2026</p>

    <h2>Purpose</h2>
    <p>Garmin Battery Alert monitors battery state on a compatible Garmin watch and sends battery-related notifications requested by the user.</p>

    <h2>Data processed</h2>
    <p>For alert delivery, the application may transmit the watch battery percentage, charging status, alert or event type, a generated event identifier, and alert message text.</p>
    <p>The application does not intentionally collect GPS or location data, heart rate, activity history, contacts, Garmin account credentials, health profile information, or advertising identifiers.</p>

    <h2>Local watch data</h2>
    <p>The watch may locally store alert armed or disarmed state, pending alert information, and delivery or retry diagnostics. This information is used for alert operation and reliable retry behavior.</p>

    <h2>Cloudflare relay</h2>
    <p>Alert information is sent to the Garmin Battery Alert Cloudflare Worker solely to authenticate, process, deduplicate, and deliver the requested notification. The relay uses a generated event ID to prevent duplicate Telegram messages.</p>
    <p>After a notification is successfully delivered, the relay stores only the successfully delivered event identifier and its delivery timestamp for deduplication.</p>

    <h2>Telegram</h2>
    <p>The relay sends the alert notification to the user's configured Telegram chat using Telegram's Bot API. Telegram is a third-party service, and information sent to Telegram is subject to Telegram's own handling and privacy terms. Garmin does not receive the Telegram message.</p>

    <h2>Use of data</h2>
    <p>Data is used only for determining and delivering battery alerts, retrying failed delivery, preventing duplicate delivery, and operational troubleshooting.</p>

    <h2>No sale, advertising, or tracking</h2>
    <p>No data is sold. The application and relay perform no advertising and do not use data for behavioral profiling or marketing. This page uses no JavaScript, analytics, or tracking, and the application code does not create cookies.</p>

    <h2>Garmin disclaimer</h2>
    <p>Information submitted by the application is submitted to the application developer and relay service, not to Garmin. Garmin is not responsible for that data.</p>

    <h2>Security</h2>
    <p>The relay requires authentication for alert delivery, communications use HTTPS, and credentials are not intentionally included in alert payloads.</p>

    <h2>Data retention and deletion</h2>
    <p>Pending alert information remains on the watch until it is delivered or otherwise cleared by application state. The relay currently stores only the successfully delivered event identifier and delivery timestamp for deduplication. The relay does not currently enforce a fixed automatic deletion schedule for those records.</p>

    <h2>Contact</h2>
    <p>For privacy questions regarding Garmin Battery Alert, please use the developer contact information provided with the Garmin Connect IQ app listing.</p>
  </main>
</body>
</html>`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function validatePayload(value: unknown): AlertPayload | string {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return "Request body must be a JSON object";
  }

  const payload = value as Record<string, unknown>;
  if (typeof payload.event_id !== "string" || payload.event_id.trim().length === 0 || payload.event_id.length > 128) {
    return "event_id must be a non-empty string of at most 128 characters";
  }
  if (payload.event_type !== "test" && payload.event_type !== "low_battery" && payload.event_type !== "full_charge") {
    return "event_type is unsupported";
  }
  if (typeof payload.battery !== "number" || !Number.isFinite(payload.battery) || payload.battery < 0 || payload.battery > 100) {
    return "battery must be a finite number from 0 through 100";
  }
  if (typeof payload.charging !== "boolean") {
    return "charging must be a boolean";
  }
  if (typeof payload.message !== "string" || payload.message.trim().length === 0 || payload.message.length > 500) {
    return "message must be a non-empty string of at most 500 characters";
  }

  return payload as unknown as AlertPayload;
}

function telegramText(payload: AlertPayload): string {
  return [
    "Garmin Battery Alert",
    `Event: ${payload.event_type}`,
    `Event ID: ${payload.event_id}`,
    `Battery: ${payload.battery.toFixed(1)}%`,
    `Charging: ${payload.charging ? "Yes" : "No"}`,
    `Message: ${payload.message}`,
  ].join("\n");
}

export class RelayIdempotency {
  private state: DurableObjectState;
  private env: Env;
  private fetcher: Fetcher;
  private inFlight = new Map<string, Promise<DeliveryResult>>();

  constructor(state: DurableObjectState, env: Env, fetcher: Fetcher = fetch) {
    this.state = state;
    this.env = env;
    // Cloudflare runtime APIs are receiver-sensitive. Keep fetch as a standalone
    // call instead of invoking the captured global as a Durable Object method.
    this.fetcher = (input, init) => fetcher(input, init);
    this.state.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS delivered_events (
        event_id TEXT PRIMARY KEY,
        delivered_at TEXT NOT NULL
      )
    `);
  }

  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return json({ ok: false, error: "not_found" }, 404);
    }

    const payload = await request.json() as AlertPayload;
    if (this.wasDelivered(payload.event_id)) {
      return json({ ok: true, delivered: true, duplicate: true, event_id: payload.event_id });
    }

    const existing = this.inFlight.get(payload.event_id);
    if (existing) {
      const result = await existing;
      if (result.body.delivered === true) {
        return json({ ...result.body, duplicate: true }, result.status);
      }
      return json(result.body, result.status);
    }

    const attempt = this.deliver(payload);
    this.inFlight.set(payload.event_id, attempt);
    try {
      const result = await attempt;
      return json(result.body, result.status);
    } finally {
      this.inFlight.delete(payload.event_id);
    }
  }

  private wasDelivered(eventId: string): boolean {
    const rows = this.state.storage.sql.exec<{ delivered_at: string }>(
      "SELECT delivered_at FROM delivered_events WHERE event_id = ? LIMIT 1",
      eventId,
    );
    return !rows[Symbol.iterator]().next().done;
  }

  private async deliver(payload: AlertPayload): Promise<DeliveryResult> {
    try {
      const telegramResponse = await this.fetcher(
        `https://api.telegram.org/bot${this.env.TELEGRAM_BOT_TOKEN}/sendMessage`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ chat_id: this.env.TELEGRAM_CHAT_ID, text: telegramText(payload) }),
        },
      );

      if (!telegramResponse.ok) {
        return { status: 502, body: { ok: false, error: "telegram_delivery_failed" } };
      }

      const telegramResult = await telegramResponse.json() as { ok?: boolean };
      if (telegramResult.ok !== true) {
        return { status: 502, body: { ok: false, error: "telegram_delivery_failed" } };
      }

      this.state.storage.sql.exec(
        "INSERT OR IGNORE INTO delivered_events (event_id, delivered_at) VALUES (?, ?)",
        payload.event_id,
        new Date().toISOString(),
      );
      return {
        status: 200,
        body: { ok: true, delivered: true, duplicate: false, event_id: payload.event_id },
      };
    } catch (error) {
      const errorName = error instanceof Error ? error.name : "UnknownError";
      const errorMessage = error instanceof Error ? error.message : "Unknown delivery exception";
      console.error("relay_delivery_exception", {
        stage: "telegram_fetch_or_parse",
        event_id: payload.event_id,
        exception_name: errorName,
        exception_message: this.redact(errorMessage),
        telegram_bot_token_present: Boolean(this.env.TELEGRAM_BOT_TOKEN),
        telegram_chat_id_present: Boolean(this.env.TELEGRAM_CHAT_ID),
      });
      return { status: 502, body: { ok: false, error: "telegram_delivery_failed" } };
    }
  }

  private redact(value: string): string {
    let sanitized = value;
    for (const secret of [this.env.TELEGRAM_BOT_TOKEN, this.env.TELEGRAM_CHAT_ID, this.env.RELAY_API_KEY]) {
      if (secret) sanitized = sanitized.split(secret).join("[REDACTED]");
    }
    return sanitized;
  }
}

export function createHandler() {
  return async function handle(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({
        service: "garmin-battery-alert-relay",
        version: "0.2.0",
        status: "ok",
        worker_version_id: env.CF_VERSION_METADATA.id,
      });
    }

    if (request.method === "GET" && url.pathname === "/privacy") {
      return new Response(PRIVACY_POLICY_HTML, { status: 200, headers: HTML_HEADERS });
    }

    if (request.method !== "POST" || url.pathname !== "/alert") {
      return json({ ok: false, error: "not_found" }, 404);
    }

    if (request.headers.get("authorization") !== `Bearer ${env.RELAY_API_KEY}`) {
      return json({ ok: false, error: "unauthorized" }, 401);
    }

    const contentType = request.headers.get("content-type") || "";
    if (contentType.split(";", 1)[0].trim().toLowerCase() !== "application/json") {
      return json({ ok: false, error: "unsupported_media_type" }, 415);
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json({ ok: false, error: "malformed_json" }, 400);
    }

    const payload = validatePayload(body);
    if (typeof payload === "string") {
      return json({ ok: false, error: "invalid_payload", detail: payload }, 400);
    }

    const id = env.IDEMPOTENCY.idFromName("telegram-relay");
    return env.IDEMPOTENCY.get(id).fetch(new Request("https://idempotency.internal/deliver", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    }));
  };
}

const handle = createHandler();

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env);
  },
};
