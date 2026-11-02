# Dynamic Pricing Proxy

A Rails API that serves hotel room rates from Tripla's dynamic pricing model. The model is expensive to run and limited to 1,000 calls a day, while the API needs to handle at least 10,000 requests a day with rates no older than 5 minutes.

A background worker fetches all the rates and keeps them in Redis. Requests only ever read from Redis, so traffic can't use up the quota, and users never wait on the pricing model.

- [spec.md](spec.md): the original assignment brief
- [DECISIONS.md](DECISIONS.md): the audit log of every decision and change
- [openapi/public_api.yaml](openapi/public_api.yaml): the API reference, generated from the specs

## Setup

Everything runs in Docker, so you don't need Ruby installed on your machine. You need Docker with Compose V2, which provides the `docker compose` command rather than the older `docker-compose`. This was tested with Docker Engine 29.7.2 and Compose 5.5.0. Earlier versions should work, as nothing here relies on recent features, but they haven't been tested.

1. Create your local compose file. It is gitignored, so your token stays out of the repository:

   ```bash
   cp docker-compose.example.yml docker-compose.yml
   ```

2. In `docker-compose.yml`, replace both copies of `REPLACE_WITH_RATE_API_TOKEN` with the token from the [rate-api documentation](https://hub.docker.com/r/tripladev/rate-api). The app won't start without it.

## Run

```bash
docker compose up -d --build

curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'
# {"rate":56700}
```

Requests return `503` until the worker's first successful fetch. That usually takes a few seconds, or up to 90s if the first attempt fails, so try again if you see one.

To see the worker's activity:

```bash
docker compose logs -f rate-refresher
```

## Test

```bash
# Full suite
docker compose exec -e RAILS_ENV=test interview-dev bundle exec rspec

# One file
docker compose exec -e RAILS_ENV=test interview-dev bundle exec rspec spec/services/pricing/rate_refresher_spec.rb

# Lint
docker compose exec interview-dev bundle exec rubocop
```

`RAILS_ENV=test` is needed because the Dockerfile sets it to `development`.

To regenerate the API reference after changing the API (CI fails if it's out of date):

```bash
docker compose exec interview-dev bin/rails openapi_ruby:generate
```

CI builds `docker-compose.yml` from the example file, so the repository needs a `RATE_API_TOKEN` Actions secret.

## API

`GET /api/v1/pricing?period=&hotel=&room=`

| Parameter | Values |
|---|---|
| `period` | `Summer`, `Autumn`, `Winter`, `Spring` |
| `hotel` | `FloatingPointResort`, `GitawayHotel`, `RecursionRetreat` |
| `room` | `SingletonRoom`, `BooleanTwin`, `RestfulKing` |

A successful response returns `200` with the room's current rate:

```json
{ "rate": 56700 }
```

Errors share one format:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "One or more parameters are invalid.",
    "details": [{ "field": "room", "message": "is required" }]
  }
}
```

| Status | Code | Meaning |
|---|---|---|
| `422` | `validation_failed` | A parameter is missing, invalid or not recognized |
| `429` | `rate_limited` | Over 10,000 requests a minute from one IP. See `Retry-After` |
| `500` | `internal_error` | An unexpected error |
| `502` | `rate_not_available` | No current rate for this room, while others are available |
| `503` | `pricing_unavailable` | No current rates, or Redis is down |

## Logging

Everything is logged as one JSON object per line, on stdout in production. In development, `docker compose logs` shows it.

| Event | Level | Meaning |
|---|---|---|
| `http_request` | info | One line per request, with status, duration, `params`, and `error_code` on failure |
| `rate_refresh_succeeded` | info | The worker stored new rates |
| `rate_refresh_failed` | info | A refresh attempt failed, and the worker will try again |
| `rate_api_request` | info | One call to the pricing model, with status and duration |
| `rate_api_missing_rows`, `rate_api_invalid_row`, `rate_api_unexpected_row`, `rate_api_duplicate_row` | warn | A response had a problem with its rows |
| `cache_unavailable`, `unhandled_error`, `rate_refresh_error` | error | Redis or an unexpected failure |

Two IDs link related lines:

- **`request_id`:** matches the `X-Request-Id` header returned to the client, so a reported failure can be traced to its log lines.
- **`refresh_id`:** one per worker attempt, linking its API call, row warnings and result.

```bash
docker compose logs interview-dev | grep <request_id>
docker compose logs rate-refresher | grep <refresh_id>
```

Throttled requests aren't logged, because a client over the limit could flood the logs. Logging an IP after a number of throttles would be a future option. There are no metrics or tracing, but production alerts can be built on these events.

## Design

### The core problem

There are 36 combinations of period, hotel and room, and 288 five-minute windows in a day. Caching each combination separately could need 36 × 288 = 10,368 calls, far over the 1,000 limit. The API accepts batches, so one call can fetch all 36.

Testing the real API changed the design further. **About 1 call in 6 fails**, with 9% returning a `500` and 7.5% hanging, one of them for over 120s. Failed calls still count against the quota. So caching good responses isn't enough: if requests fetch on a miss, an outage turns traffic into calls until the quota runs out.

### How it works

```mermaid
flowchart LR
    client[Client] -->|GET /pricing| api[Rails API]
    api -->|read only| redis[(Redis)]
    worker[bin/rate_refresher] -->|snapshot and gate| redis
    worker -->|at most 1 call per 90s| model[Pricing model]
```

- **When to refresh (180s):** every 5s, `bin/rate_refresher` checks the age of the rates. Once they're 180s old, it fetches all 36 in one call. After a success, the next refresh is 180s later.
- **How often it may call (90s):** a Redis key set atomically allows one call per 90s, successful or not. That caps usage at **960 calls a day, whatever the traffic or failures**. If Redis is down, no call is made.
- **Failures stay invisible:** the two timings work together. If the attempt at 180s fails, the rates are still due, so the worker tries again once the 90s gate clears, at 270s. The current rates stay valid until 300s, so users don't notice.
- **Freshness:** the API gives no timestamps, so each rate's 5 minutes start from just before the call is sent. Rates are never served past that, even during an outage.
- **Bad rows:** the API gives rows no identifiers, so they're matched by their values. A missing or invalid row keeps its earlier rate until that rate's own 5 minutes end, and only that room is affected. Duplicates overwrite, and rows that weren't requested are ignored. All are logged.

### Response times

Moving fetching out of the request path is also a real improvement for users. A cache hit or miss takes about 11ms at p50 on a local development stack, and a miss fails fast with a `503` rather than waiting. A request that fetched its own rates could wait up to 3s on a hung call.

### Approaches considered

| Approach | Worst-case calls/day | Result |
|---|---|---|
| Cache each combination separately | About 10,000 | Exceeds the quota |
| Batch on a cache miss | Grows with traffic during an outage | Quota can run out, and users wait on the model and see its failures |
| Batch on a miss, behind a gate and lock | 960 | Quota is safe, but users still wait, and each double failure blocks rates for 3 minutes |
| **Worker refreshes, requests only read** | **960** | **Chosen:** quota is safe, responses are fast, and most failures are invisible |

### Key decisions

| Decision | Why |
|---|---|
| Fetch all 36 rates in one call | One call per refresh, instead of up to 36 |
| Fetch in a worker, never during a request | Traffic can't spend the quota, and requests don't wait on the model |
| Allow one call per 90s, enforced in Redis | Caps usage at 960 calls a day, even if every call fails |
| Refresh at 180s, with no quick retry | Leaves time for a second attempt before rates expire, while a quick retry would need a longer gate |
| Use Redis through `Rails.cache`, and return `503` if it's down | The quota is per token, so state must be shared. An outage can't be mistaken for a cache miss |
| Give each rate its own timestamp | A rate kept after a missing row can't pass its own 5 minutes |
| Set 1s connect and 2s read timeouts | Successful calls took 43ms at most, while hung calls never returned |
| Keep the worker as a plain loop | What to do depends on the age of the rates rather than the time of day, so a scheduler adds little |
| Use one error format from a central registry | Clients get stable codes, and every failure has the same shape |
| Validate parameters with a request model | The valid values live in one place, and every bad field is reported at once |
| Generate API docs from the specs | The docs are tested against real responses, and CI catches drift |

### Trade-offs of using a worker

The alternative is fetching during the request whenever the cache is empty. Compared with that, a worker gives:

- **Fast responses:** users never wait on the pricing model, so a request takes about 11ms whether it hits or misses the cache.
- **Easier scaling with users:** requests only read Redis, so more traffic adds no calls to the model.
- **Easier control of the quota:** one process decides when to call, instead of the call rate depending on traffic.
- **Hidden failures:** a failed refresh is tried again while the current rates are still valid, so users rarely see it.
- **Fresher rates:** rates are normally replaced at about 3 minutes, not at the 5-minute limit.
- **Simpler requests:** a request has one job, which makes it easier to reason about and test.

The costs are:

- **Poor scaling with the catalogue:** combinations multiply, so one more hotel adds 12 today. Each refresh fetches all of them, whether or not anyone asks. The quota allows about two batches per window if the catalogue outgrows one request, and every request reads the whole snapshot, which slows as it grows.
- **Wasted data:** if one hotel gets most of the traffic, most fetched rates are never served. This is small at 36 combinations, and gets worse as the catalogue grows.
- **Cost with no traffic:** about 520 calls a day even overnight, against about 345 a day under constant traffic if requests fetched on demand, and none when idle.
- **Errors instead of waiting:** during a gap or at startup, users get an immediate `503`, where fetching on demand might have succeeded after a short wait. Gaps happen when the attempts at 180s and 270s both fail, about 12 times a day, and last up to 60s.
- **Another process to run:** if the worker stops, requests return `503` within 5 minutes and nothing alerts. Production should alert on `503` rates, or on `rate_refresh_succeeded` logs stopping.

The first two costs could be reduced together by refreshing only recently requested combinations. That isn't needed at this size, but it's the likely next step if the catalogue grows.

The 960 cap assumes nothing else uses the token and Redis keeps the gate. A Redis wipe could allow one extra call. The failure-based estimates come from one test run of 970 calls against the simulated API.

### Assumptions

- The catalogue stays at 36 combinations. The API documents no batch size limit, and only 36 items have been tested. If it outgrew one request, the quota would allow only about two batches per window, so going further would need a higher quota, more tokens, or fetching only the combinations in demand.
- `rate` is returned as an integer. The API documentation shows strings, but it returns integers.
- Returning an error is better than serving a rate past 5 minutes.
- Behind a proxy, Rails must be configured to trust it, or all clients would share one rate limit.
- `origins "*"` in the CORS config should be narrowed before production if browsers will call the API directly.

## AI assistance

This solution was developed with Claude Code, in the VS Code extension. It was used across the whole solution: reading the brief and API documentation, testing the live API, proposing designs, writing code, specs and documentation, and running checks.

The workflow was iterative. The author directed the design and made the key decisions, including moving fetching to a worker, keeping earlier rates for missing rows, and never letting traffic reach the quota. Each change was proposed, tested, and committed only after the author approved it.
