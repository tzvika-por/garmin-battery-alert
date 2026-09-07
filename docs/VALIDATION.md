# Validation

Garmin Battery Alert has been validated end-to-end on a physical Garmin vivoactive 4. No compatibility claim is made for another device.

## Production path

The verified path is:

```text
Garmin vivoactive 4
-> Connect IQ background execution
-> Cloudflare Worker
-> Durable Object idempotency
-> Telegram Bot API
-> destination Telegram chat
```

## Controlled relay test

The relay API key was provisioned through Connect IQ App Settings while the relay URL remained the canonical production default. The watch diagnostic changed from `Relay: Missing` to `Relay: Configured`.

After the user deliberately selected `Queue relay test`, the watch displayed `Test queued`. The foreground app was then closed. The next scheduled background execution delivered the persisted test event through the complete production path. Telegram received one message, and the watch subsequently displayed:

- `Pending: None`
- `Delivery: Delivered`
- `HTTP: 200`
- `Schedule: Every 5 min`

The troubleshooting action does not send from the foreground, does not alter either alert's armed/disarmed state, and refuses to overwrite an existing pending event.

## Natural battery-condition validation

All four state-machine transitions were observed under real battery conditions:

| Transition | Physical result | Evidence |
|---|---|---|
| Full trigger: battery `>= 99%` and charging | PASS | A `full_charge` event was generated at 99.0% with charging reported as Yes and delivered to Telegram. |
| Full rearm: not charging and battery `<= 95%` | PASS | After unplugging and discharging to 95% or below, the watch showed `Full alert: Armed`. |
| Low trigger: battery `<= 5%` and not charging | PASS | A `low_battery` event was generated at 5.0% with charging reported as No and delivered to Telegram. |
| Low rearm: battery `>= 10%` | PASS | After charging past 10%, the watch showed `Low alert: Armed`. |

Rearm transitions are internal state changes. No Telegram message is expected or generated for a rearm.

## Background behavior

Scheduled checks were observed continuing while the foreground app was closed. Battery readings and the last-check diagnostic advanced during normal five-minute background execution.

Pending events are persisted before network delivery. A failed attempt retains the original event ID and payload for a later scheduled retry. Only an HTTP 200 response containing `delivered: true` clears the pending event.

## Relay idempotency

The Cloudflare Worker uses one SQLite-backed Durable Object. Validation covered:

- The first successful event delivery calls Telegram and records the event ID.
- A later request with the same delivered event ID returns success as a duplicate without calling Telegram again.
- Concurrent requests with one event ID share a single delivery attempt.
- Failed Telegram attempts are not recorded and remain retryable.
- Different event IDs remain independent.

Automated Worker tests use a mocked Telegram response and do not send real messages.

## Build and automated validation

The validated baseline passed:

- Normal vivoactive4 PRG build
- Clean minimal-environment PRG build
- Strict Monkey C type-check level 3
- Monkey C state-machine, persistence, response, and test-action tests
- Intentional failed-build safety check without replacing the last successful artifact
- Worker unit tests
- Strict TypeScript type-check
- Wrangler dry-run bundle

Successful compiler runs produced no warnings. Build artifacts and credentials are intentionally excluded from Git.

## Status

The vivoactive4 application, background scheduling, all four battery trigger/rearm transitions, authenticated relay delivery, Durable Object idempotency, and Telegram delivery are physically verified. The canonical system is operational under real battery conditions.
