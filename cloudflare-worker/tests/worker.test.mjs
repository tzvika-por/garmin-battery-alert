import assert from "node:assert/strict";
import test from "node:test";
import { createHandler, RelayIdempotency } from "../src/index.ts";

const baseEnv = {
  TELEGRAM_BOT_TOKEN: "unit-test-bot-token",
  TELEGRAM_CHAT_ID: "unit-test-chat-id",
  RELAY_API_KEY: "unit-test-relay-key",
  CF_VERSION_METADATA: {
    id: "unit-test-worker-version",
    tag: "",
    timestamp: "2026-08-11T00:00:00.000Z",
  },
};

const validPayload = {
  event_id: "manual-test-001",
  event_type: "test",
  battery: 80.0,
  charging: false,
  message: "Garmin Battery Alert relay test",
};

class MemorySql {
  delivered = new Map();

  exec(query, ...bindings) {
    if (query.includes("SELECT delivered_at")) {
      const deliveredAt = this.delivered.get(bindings[0]);
      return deliveredAt ? [{ delivered_at: deliveredAt }] : [];
    }
    if (query.includes("INSERT OR IGNORE")) {
      if (!this.delivered.has(bindings[0])) this.delivered.set(bindings[0], bindings[1]);
    }
    return [];
  }
}

function makeEnv(fetcher = async () => new Response(JSON.stringify({ ok: true }), { status: 200 })) {
  const sql = new MemorySql();
  const state = { storage: { sql } };
  let object;
  const env = {
    ...baseEnv,
    IDEMPOTENCY: {
      idFromName: (name) => name,
      get: () => ({ fetch: (request) => object.fetch(request) }),
    },
  };
  object = new RelayIdempotency(state, env, fetcher);
  return { env, sql, object };
}

function request(body = validPayload, options = {}) {
  return new Request("https://relay.test/alert", {
    method: "POST",
    headers: {
      authorization: `Bearer ${baseEnv.RELAY_API_KEY}`,
      "content-type": "application/json",
      ...options.headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function responseJson(response) {
  return { status: response.status, body: await response.json() };
}

test("GET /health returns non-sensitive status", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(new Request("https://relay.test/health"), env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    service: "garmin-battery-alert-relay",
    version: "0.2.0",
    status: "ok",
    worker_version_id: "unit-test-worker-version",
  });
});

test("GET /privacy is public HTML with UTF-8 encoding", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(new Request("https://relay.test/privacy"), env);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "text/html; charset=UTF-8");
});

test("GET /privacy contains the required policy content", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(new Request("https://relay.test/privacy"), env);
  const text = await response.text();
  for (const requiredText of [
    "Garmin Battery Alert Privacy Policy",
    "Effective date:</strong> August 18, 2026",
    "battery percentage",
    "charging status",
    "Cloudflare",
    "Telegram",
    "submitted to the application developer and relay service, not to Garmin",
  ]) {
    assert.equal(text.includes(requiredText), true, `missing required policy text: ${requiredText}`);
  }
});

test("GET /privacy contains no configured secret values", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(new Request("https://relay.test/privacy"), env);
  const text = await response.text();
  assert.equal(text.includes(env.TELEGRAM_BOT_TOKEN), false);
  assert.equal(text.includes(env.TELEGRAM_CHAT_ID), false);
  assert.equal(text.includes(env.RELAY_API_KEY), false);
});

test("GET /privacy contains no scripts, tracking, or external assets", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(new Request("https://relay.test/privacy"), env);
  const text = await response.text();
  assert.equal(/<script\b/i.test(text), false);
  assert.equal(/<(img|iframe)\b/i.test(text), false);
  assert.equal(/<link\b[^>]*rel=["']?(stylesheet|preload)/i.test(text), false);
  assert.equal(response.headers.has("set-cookie"), false);
});

test("missing Authorization returns 401", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(request(validPayload, { headers: { authorization: "" } }), env);
  assert.equal(response.status, 401);
});

test("wrong Bearer secret returns 401", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(request(validPayload, { headers: { authorization: "Bearer wrong" } }), env);
  assert.equal(response.status, 401);
});

test("malformed JSON returns 400", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(request("{"), env);
  assert.equal(response.status, 400);
});

for (const battery of [-0.1, 100.1]) {
  test(`invalid battery ${battery} returns 400`, async () => {
    const { env } = makeEnv();
    const response = await createHandler()(request({ ...validPayload, battery }), env);
    assert.equal(response.status, 400);
  });
}

test("unsupported event type returns 400", async () => {
  const { env } = makeEnv();
  const response = await createHandler()(request({ ...validPayload, event_type: "unknown" }), env);
  assert.equal(response.status, 400);
});

test("missing required field returns 400", async () => {
  const { message: _message, ...incomplete } = validPayload;
  const { env } = makeEnv();
  const response = await createHandler()(request(incomplete), env);
  assert.equal(response.status, 400);
});

test("first event sends Telegram once and records delivery", async () => {
  let calls = 0;
  const { env } = makeEnv(async () => { calls += 1; return new Response(JSON.stringify({ ok: true })); });
  const result = await responseJson(await createHandler()(request(), env));
  assert.deepEqual(result, { status: 200, body: { ok: true, delivered: true, duplicate: false, event_id: "manual-test-001" } });
  assert.equal(calls, 1);
});

test("outbound fetch is invoked without a Durable Object receiver", async () => {
  let receiver;
  function receiverSensitiveFetch() {
    receiver = this;
    if (this !== undefined) throw new TypeError("Illegal invocation: incorrect this reference");
    return Promise.resolve(new Response(JSON.stringify({ ok: true })));
  }
  const { env } = makeEnv(receiverSensitiveFetch);
  const result = await responseJson(await createHandler()(request(), env));
  assert.equal(result.status, 200);
  assert.equal(receiver, undefined);
});

test("same event_id is a duplicate and does not resend Telegram", async () => {
  let calls = 0;
  const { env } = makeEnv(async () => { calls += 1; return new Response(JSON.stringify({ ok: true })); });
  await createHandler()(request(), env);
  const result = await responseJson(await createHandler()(request(), env));
  assert.deepEqual(result, { status: 200, body: { ok: true, delivered: true, duplicate: true, event_id: "manual-test-001" } });
  assert.equal(calls, 1);
});

test("different event_id sends Telegram normally", async () => {
  let calls = 0;
  const { env } = makeEnv(async () => { calls += 1; return new Response(JSON.stringify({ ok: true })); });
  await createHandler()(request(), env);
  const second = await responseJson(await createHandler()(request({ ...validPayload, event_id: "manual-test-002" }), env));
  assert.equal(second.body.duplicate, false);
  assert.equal(calls, 2);
});

test("Telegram HTTP failure is not recorded", async () => {
  const { env, sql } = makeEnv(async () => new Response("failure", { status: 500 }));
  const result = await responseJson(await createHandler()(request(), env));
  assert.deepEqual(result, { status: 502, body: { ok: false, error: "telegram_delivery_failed" } });
  assert.equal(sql.delivered.size, 0);
});

test("Telegram ok:false is not recorded", async () => {
  const { env, sql } = makeEnv(async () => new Response(JSON.stringify({ ok: false }), { status: 200 }));
  const result = await responseJson(await createHandler()(request(), env));
  assert.deepEqual(result, { status: 502, body: { ok: false, error: "telegram_delivery_failed" } });
  assert.equal(sql.delivered.size, 0);
});

test("retry after Telegram failure attempts again and succeeds", async () => {
  let calls = 0;
  const { env } = makeEnv(async () => {
    calls += 1;
    return new Response(JSON.stringify({ ok: calls > 1 }), { status: 200 });
  });
  const first = await createHandler()(request(), env);
  const second = await responseJson(await createHandler()(request(), env));
  assert.equal(first.status, 502);
  assert.equal(second.status, 200);
  assert.equal(second.body.duplicate, false);
  assert.equal(calls, 2);
});

test("concurrent duplicate requests perform one Telegram send", async () => {
  let calls = 0;
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const { env } = makeEnv(async () => {
    calls += 1;
    await gate;
    return new Response(JSON.stringify({ ok: true }));
  });
  const firstPromise = createHandler()(request(), env);
  const secondPromise = createHandler()(request(), env);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(calls, 1);
  release();
  const [first, second] = await Promise.all([firstPromise, secondPromise]);
  assert.equal((await first.json()).duplicate, false);
  assert.equal((await second.json()).duplicate, true);
  assert.equal(calls, 1);
});

test("duplicate response contains no secrets", async () => {
  const { env } = makeEnv();
  await createHandler()(request(), env);
  const response = await createHandler()(request(), env);
  const text = await response.text();
  assert.equal(text.includes(env.TELEGRAM_BOT_TOKEN), false);
  assert.equal(text.includes(env.TELEGRAM_CHAT_ID), false);
  assert.equal(text.includes(env.RELAY_API_KEY), false);
});

test("normal API responses do not leak secrets", async () => {
  const { env } = makeEnv();
  const responses = [
    await createHandler()(new Request("https://relay.test/health"), env),
    await createHandler()(new Request("https://relay.test/privacy"), env),
    await createHandler()(request(validPayload, { headers: { authorization: "Bearer wrong" } }), env),
    await createHandler()(request(), env),
  ];
  for (const response of responses) {
    const text = await response.text();
    assert.equal(text.includes(env.TELEGRAM_BOT_TOKEN), false);
    assert.equal(text.includes(env.TELEGRAM_CHAT_ID), false);
    assert.equal(text.includes(env.RELAY_API_KEY), false);
  }
});
