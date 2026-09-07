# Garmin Battery Alert Relay

This directory contains the Cloudflare Worker used by Garmin Battery Alert. It validates authenticated watch events, applies Durable Object idempotency, and sends accepted events through the Telegram Bot API.

Deploy your own copy for development or personal use. The canonical Worker is not a shared public relay.

## Endpoints

- `GET /health` — non-sensitive service and Worker-version status
- `GET /privacy` — public privacy policy for the deployment
- `POST /alert` — authenticated JSON alert delivery

`POST /alert` requires `Authorization: Bearer <RELAY_API_KEY>` and accepts `test`, `low_battery`, or `full_charge` events. The Worker creates Telegram text server-side; callers cannot provide Telegram credentials or select a destination chat.

## Requirements

- Node.js and pnpm
- A Cloudflare account authenticated with Wrangler
- A Telegram bot token and destination chat ID
- A cryptographically random relay API key

The canonical project was validated with Node.js 24.14.0, pnpm 11.16.0, TypeScript 5.9, and Wrangler 4.x.

## Local installation

```sh
pnpm install --frozen-lockfile
```

For local Worker development, copy the placeholder file and replace values only in the ignored copy:

```sh
cp .dev.vars.example .dev.vars
```

Never commit `.dev.vars`, `.env` files, or real credentials.

## Required secrets

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `RELAY_API_KEY`

Set production values through Wrangler's interactive secret prompts:

```sh
pnpm wrangler secret put TELEGRAM_BOT_TOKEN
pnpm wrangler secret put TELEGRAM_CHAT_ID
pnpm wrangler secret put RELAY_API_KEY
```

The watch receives only `RELAY_API_KEY`. The Telegram token and chat ID remain on Cloudflare.

## Tests and validation

```sh
pnpm test
pnpm typecheck
pnpm check
```

- `pnpm test` runs Node unit tests with mocked Cloudflare and Telegram behavior.
- `pnpm typecheck` runs strict TypeScript checking without emitting files.
- `pnpm check` asks Wrangler to create a dry-run bundle and does not deploy.

Unit tests do not call Telegram or any production service.

## Deployment

Forks should choose a unique Worker `name` in `wrangler.jsonc`. Authenticate and verify the active Cloudflare account before deployment:

```sh
pnpm wrangler login
pnpm wrangler whoami
pnpm wrangler deploy
```

`wrangler.jsonc` declares the `IDEMPOTENCY` Durable Object binding and its SQLite migration. Wrangler applies the migration when the Worker is first deployed.

After deployment:

1. Confirm `GET /health` returns HTTP 200.
2. Configure the watch's `RelayBaseUrl` with your Worker origin.
3. Configure the watch's `RelayApiKey` with the same value as the Cloudflare secret.
4. Use one deliberate `Queue relay test` only after the watch reports `Relay: Configured` and no event is pending.

## Idempotency behavior

All relay traffic uses one stable Durable Object singleton. Successfully delivered event IDs and delivery timestamps are recorded in SQLite.

- The first successful event ID calls Telegram and returns `delivered: true, duplicate: false`.
- A later sequential or concurrent request for that delivered ID skips Telegram and returns `delivered: true, duplicate: true`.
- A failed Telegram request is not recorded, so a later watch retry remains possible.
- Different event IDs are independent.

This prevents ordinary retry duplicates. It does not claim mathematically perfect exactly-once behavior across the external Telegram API.

## Security

- Keep all three secret values out of Git, logs, test fixtures, URLs, and screenshots.
- Use a long random `RELAY_API_KEY` and rotate it if disclosed.
- Never accept a Telegram token or chat ID from an alert request.
- Review Cloudflare bindings and routes before every deployment.
- Do not reuse the canonical project's relay or credentials.

## Privacy

`GET /privacy` serves a self-contained policy without JavaScript, analytics, tracking, application-created cookies, or external assets. Forks and self-hosters must review the text and publish privacy information that accurately describes their own deployment and data handling.

The canonical policy is available at:

<https://garmin-battery-alert-relay.garmin-battery-alert-relay.workers.dev/privacy>
