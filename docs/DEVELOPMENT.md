# Development notes

This document records the behavioral invariants and contributor-facing details that should remain stable when changing Garmin Battery Alert.

## Design invariants

- Target device: `vivoactive4` only.
- Minimum Connect IQ API: 3.2.0.
- Battery decisions use the raw `Float` returned by Garmin, not the rounded display value.
- Low trigger: battery `<= 5%` while not charging.
- Low rearm: battery `>= 10%`.
- Full trigger: battery `>= 99%` while charging.
- Full rearm: not charging and battery `<= 95%`.
- Low and full armed states are independent and persisted.
- Rearm transitions do not create relay events.
- Temporal schedule registration occurs only from the foreground application path.
- Background execution always reaches `Background.exit(null)`, either directly or after the communications callback.

## Delivery invariants

- A triggered event is persisted before any network attempt.
- A pending event retains one stable event ID and its original payload across retries.
- An existing pending event is never overwritten by another trigger or by `Queue relay test`.
- Each background invocation attempts at most one delivery.
- Only HTTP 200 JSON with `delivered: true` clears the pending event.
- Network errors, HTTP errors, malformed responses, and callback errors retain the event.
- A Durable Object duplicate response with `delivered: true` counts as success.
- Telegram credentials stay on Cloudflare and are never sent to the watch.

## Foreground relay test

`Queue relay test` is an intentional troubleshooting feature. It requires deliberate user input and queues a `test` event through the same storage, background scheduling, authentication, retry, and idempotency path as a real alert.

The action does not read, evaluate, arm, disarm, or persist either battery-alert state. It refuses to replace any pending event.

## Application settings

- `RelayApiKey` is a password setting with an empty default.
- `RelayBaseUrl` is the relay origin and must not include `/alert`.
- The manifest requires `Background` and `Communications` permissions.

The committed production application ID belongs to the canonical project. Forks that publish or distribute a separate application must generate their own production and Beta IDs. Every Beta package build requires `GARMIN_BETA_APP_ID`; no maintainer identity is used as a fallback.

## Local configuration

Copy `config/build.env.example` to the ignored `config/build.env`, replace its placeholders, and source it before running a build. Never commit developer keys or environment values.

The build scripts require:

- `CONNECT_IQ_SDK` — installed Connect IQ SDK directory containing `bin/monkeyc`
- `GARMIN_DEVELOPER_KEY` — readable Garmin developer-key file

The Beta build additionally requires:

- `GARMIN_BETA_APP_ID` — lowercase UUID for a Beta application identity owned by the builder

Both scripts derive the repository root from their own location and atomically promote successful output. Failed builds leave the prior successful artifact in place.

## Validation before a change is accepted

Run the checks relevant to the changed component:

```sh
cd cloudflare-worker
pnpm test
pnpm typecheck
pnpm check
```

For watch changes, run the Monkey C tests for `vivoactive4`, the normal PRG build, and strict level-3 type checking. Changes to packaging should also run the Beta IQ build and a deliberate failed-build safety check.

Before any production deployment or physical-watch test:

1. Confirm the exact target, application identity, permissions, and relay URL.
2. Confirm secrets are absent from source, resources, build output, logs, and command history.
3. Verify the Worker version through `/health` before authenticated traffic.
4. Send no more production test messages than the validation requires.

## Project assistance

The project was developed with substantial assistance from OpenAI Codex across implementation, testing, debugging, documentation, and project setup. Physical behavior and the production delivery path were validated on an actual vivoactive 4. OpenAI does not endorse, maintain, or support the project.
