# Repository guidance

## Project purpose and status

Garmin Battery Alert is a Connect IQ application for Garmin vivoactive 4. It monitors battery state during background execution and sends Telegram alerts through a Cloudflare relay.

Release `v1.0.0` is complete and physically verified end-to-end. Treat existing verified behavior as an invariant unless a task explicitly requests a behavior change.

## Architecture

The delivery path is:

`Garmin Connect IQ app -> background execution -> Cloudflare Worker -> Durable Object idempotency -> Telegram Bot API`

See [README.md](README.md) for setup and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for implementation details and invariants.

## Critical watch behavior invariants

- Low alert triggers when raw battery is `<= 5.0` and the watch is not charging.
- Low alert rearms when raw battery is `>= 10.0`.
- Full alert triggers when raw battery is `>= 99.0` and the watch is charging.
- Full alert rearms when the watch is not charging and raw battery is `<= 95.0`.
- The raw battery `Float`, not a rounded display value, drives decisions.
- Rearm changes state only and does not create an alert.
- Alert state persists through `Application.Storage`.
- Persist a pending event before attempting network delivery.
- Never overwrite an existing pending event.
- Keep the event ID and original payload stable across retries.
- Attempt at most one delivery per background invocation.
- After starting an asynchronous web request, wait for its callback before calling `Background.exit(null)`.
- Clear pending state only after HTTP 200 and a parsed `delivered: true` response.
- Treat `delivered: true` with `duplicate: true` as successful delivery.
- Retain pending state after network, authentication, HTTP, malformed-response, or callback failures.

## `Queue relay test`

`Queue relay test` is intentional troubleshooting functionality and must remain unless a task explicitly requests its removal.

It creates and persists an `event_type: test` event, then uses the normal background, retry, and delivery path. It does not send directly from the foreground, refuses to replace an existing pending event, and must not modify low- or full-alert armed-state logic.

## Cloudflare relay and idempotency

- Relay authentication uses `RELAY_API_KEY`.
- Telegram credentials and relay secrets must never be committed.
- Durable Object idempotency prevents a second Telegram message for an already delivered event ID.
- A duplicate delivered request returns `delivered: true` and `duplicate: true` without another Telegram send.
- Do not change the production deployment unless the task explicitly requests it.

## Configuration, secrets, and builds

Never commit Telegram bot tokens, Telegram chat IDs, real relay API keys, private keys, GitHub credentials or PATs, or machine-specific secret files. Public examples must contain placeholders only. The watch `RelayApiKey` default must remain empty.

Keep the build scripts portable:

- Supply `CONNECT_IQ_SDK` externally.
- Supply `GARMIN_DEVELOPER_KEY` externally.
- Require `GARMIN_BETA_APP_ID` for every Beta build.
- Do not add maintainer-specific absolute paths.
- Do not restore a maintainer Beta-ID fallback.

Do not commit generated PRG, IQ, or other build artifacts unless a task explicitly requires a reviewed public artifact.

## GarminCalBot boundary

GarminCalBot is a separate service and project. Do not modify, start, stop, migrate, inspect secrets from, or otherwise alter GarminCalBot during Garmin Battery Alert work unless the user explicitly requests a separate GarminCalBot task.

Do not add GarminCalBot backups, metadata, paths, secrets, or checksums to this repository.

## Testing expectations

Before changing code, identify the affected layer and preserve current verified behavior unless a change is explicitly requested.

After relevant changes:

- Run the applicable existing tests and compiler or type checks.
- Run build validation when practical.
- Use the repository scripts and commands documented in the README and development notes.
- Do not deploy merely to validate local changes.

For watch behavior changes, validate against [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and [docs/VALIDATION.md](docs/VALIDATION.md). Do not claim physical validation unless it was actually performed on a physical Garmin device.

## Public-repository hygiene

This is a public repository. Before committing:

- Review the complete Git diff.
- Confirm no credentials, private paths, or internal machine metadata are present.
- Keep documentation usable by external users and avoid maintainer-specific local instructions.
- Keep `.gitignore` protections intact.

Do not rewrite published history or force-push unless explicitly authorized. Do not modify existing release tags.

## Change discipline

- Prefer the smallest change that satisfies the task.
- Do not refactor unrelated code.
- Do not change thresholds or delivery semantics incidentally.
- Do not alter source, documentation, or configuration merely for cosmetic cleanup unrelated to the task.
- Update documentation when behavior or setup genuinely changes.
- Keep `README.md` public-facing, `docs/DEVELOPMENT.md` focused on implementation invariants, and `docs/VALIDATION.md` focused on validation evidence.

## AI and project context

This project was developed with substantial assistance from OpenAI Codex. That does not reduce the requirement to inspect, test, and validate changes.

Do not present OpenAI as the project owner, maintainer, licensor, or support provider.
