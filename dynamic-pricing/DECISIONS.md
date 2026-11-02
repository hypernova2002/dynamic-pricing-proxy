# Decisions and Changes

An audit log of what was decided, why, and what changed, updated with every commit. For an overview of the design, see the [README](README.md).

## Reviewing this work

The original assignment is commit `19fb148` (`19fb14848a0683f3114b4684b089dc3b6ccd42d7`, "Add customer-data-pipeline data engineer assignment"). Everything after it is this solution:

```bash
git log --reverse 19fb148..HEAD
git diff 19fb148..HEAD
```

**Status values:** Accepted (in force), Superseded (replaced by a later decision).

## Pricing model behaviour

Measured on 2026-10-30 against `tripladev/rate-api`, run through Docker Compose, with 971 batched calls on a fresh container. Where this differs from the published documentation, the code follows these results.

| Behaviour | Result | Effect on the design |
|---|---|---|
| Batch of all 36 combinations | Works. Successful calls took 3ms at p50 and 43ms at most | Batching is viable, and short timeouts are safe |
| `rate` type | Integer. The documentation shows a string | Accept both and return an integer |
| Row identifiers | None. A row is identified only by its `period`, `hotel` and `room` values, and key order shouldn't be relied on | Match rows by those three values, never by position |
| Timestamps | None. Nothing says when a rate was calculated or when it expires | Track the 5-minute window on our side, and start it before the call is sent |
| Batch size limit | None documented. Only 36 items have been tested | Batches larger than 36 are unverified |
| Repeated calls | A different rate each time | Caching is directly observable in tests and by hand |
| Random HTTP 500 | 87 of 970 calls (9%) | Failures are routine, so each one needs a clear error response |
| Random hang | 73 of 970 calls (7.5%). One test call was still hanging at 120s | Strict timeouts are essential. The scaffold has none |
| Consecutive failures | At most 3 in the run | Failures are short-lived, so the worker's next attempt usually succeeds |
| Quota exceeded | `429 {"error": "Rate limit exceeded (1000/day)"}` | The worker logs a failed attempt and tries again. Requests return `503` once rates expire |
| Quota accounting | The 429 arrived after 970 batch calls plus 30 bad-value calls, with 30 bad-token calls also sent. So 500s and hangs count against the quota, and bad tokens appear not to | Failed calls spend quota. See the known risks below |
| Bad token | `401 {"error": "Unauthorized"}` | The worker logs a failed attempt with the status. Clients never see it, and get `503` once rates expire |
| Malformed JSON | `400` with an HTML body | Don't assume error bodies are JSON |
| Quota reset time | Not measured | None for now, since the service keeps no call count |

## Decision log

| # | Date | Status | Decision | Why |
|---|---|---|---|---|
| 1 | 2026-10-30 | Accepted | Commit `docker-compose.example.yml` and gitignore `docker-compose.yml` | Keeps keys out of the repository. Environment variables stay in the compose file, with no `.env` files |
| 2 | 2026-10-30 | Accepted | Move the assignment brief to `spec.md` and keep it unchanged | Frees `README.md` for this project and preserves the original requirements |
| 3 | 2026-10-30 | Accepted | Remove the token default from `RateApiClient`, so a missing `RATE_API_TOKEN` fails at load | A default in source defeats decision 1 |
| 4 | 2026-10-30 | Accepted | CI builds `docker-compose.yml` from the example using a `RATE_API_TOKEN` Actions secret | CI needs the file now that it's untracked, and its endpoint check needs a valid token |
| 5 | 2026-10-30 | Accepted | Fetch all 36 combinations in one batched call and cache them as one snapshot for 5 minutes | Caps healthy traffic at 288 windows a day. Caching each combination separately could reach 10,000 calls against a limit of 1,000 |
| 6 | 2026-10-30 | Accepted | Use Redis through `Rails.cache` | The quota is per token, so state must be shared across processes |
| 7 | 2026-10-30 | Accepted | Never serve a rate older than 5 minutes, and start the clock before the upstream call is sent | Rate validity is a hard requirement, so an outage returns an error rather than an old price |
| 8 | 2026-10-30 | Accepted | Return errors as `{ "error": { "code", "message", "details" } }`, from a central registry | Gives clients stable codes and field-level detail, and every failure the same shape. Replaces the scaffold's `{ "error": "message" }` and its tests |
| 9 | 2026-10-30 | Accepted | Use RSpec instead of Minitest, and add Alba, rack-attack and json_model_rb | The author's preferred stack for Rails APIs. The brief allows changing dependencies, and each one's use here is described in the change log |
| 10 | 2026-10-30 | Accepted | Use a json_model_rb request model for the pricing query parameters | Declares the valid values in one place. Request models usually describe bodies, so this extends the pattern to a GET |
| 11 | 2026-10-30 | Superseded by 20 | No distributed lock. Cache only valid results through `Rails.cache.fetch` | Calls take milliseconds at 0.12 requests a second, so concurrent misses are rare. Concurrent fetches may overwrite each other, but each result is still fresh |
| 12 | 2026-10-30 | Accepted | Make Redis errors raise through the cache store's `error_handler`, returning 503 | `Rails.cache` otherwise reports Redis errors as cache misses, and each miss would spend quota |
| 13 | 2026-10-30 | Accepted | Set a 1s connect and 2s read timeout on upstream calls | Hangs lasted over 120s in testing, while successful calls took 43ms at most |
| 14 | 2026-10-30 | Superseded by 20 and 22 | No retries, failure backoff or daily call counter | Chosen by the author for simplicity. The next request after a failure simply tries again |
| 15 | 2026-10-30 | Accepted | Generate API docs with openapi-ruby from the RSpec request specs | Moving to RSpec (decision 9) makes this possible. It keeps the docs in sync with the tests |
| 16 | 2026-10-30 | Accepted | Update this document in every commit | So each commit carries its own reasoning |
| 17 | 2026-10-31 | Accepted | A missing or invalid row keeps its earlier rate until that rate's own 5 minutes end, then returns `502` for that combination only. Valid rows are still used | One bad row shouldn't block the other 35 prices or discard a rate that is still valid. Each row therefore needs its own timestamp, so a row kept from an earlier fetch can't exceed the limit |
| 18 | 2026-10-31 | Accepted | Duplicate rows overwrite, so the last one wins, and are logged | Rows have no identifiers to tell them apart, and rates vary per call, so duplicates may disagree |
| 19 | 2026-10-31 | Accepted | Rows that weren't requested are ignored and logged | With no identifiers they can't be matched to anything, so they shouldn't be cached |
| 20 | 2026-10-31 | Accepted | Never let traffic decide how often the API is called: a worker refreshes the cache, requests only read it, and one Redis key allows at most one call every 90s | The quota must never be hit, whatever the traffic. This caps calls at 960 a day. It also means a request never waits on the pricing model (decision 24). Replaces decisions 11 and 14 |
| 21 | 2026-10-31 | Accepted | Run the worker as a loop in `bin/rate_refresher`, refreshing once rates reach 180s of age | What to do depends on the age of the rates and the last attempt, not the time of day. Cron can only run once a minute, and rake adds nothing to a process that never exits |
| 22 | 2026-10-31 | Accepted | No quick retry. The next attempt comes 90s later | A quick retry would need a 180s gate to keep the 960 limit. It gives no benefit while rates are still valid, and spaced attempts cope better with a problem that lasts more than a moment |
| 23 | 2026-10-31 | Accepted | Log failed refresh attempts at `info` | There are no quick retries to keep quiet, so each failure is worth seeing at the production default level |
| 24 | 2026-10-31 | Accepted | Requests fail fast on a cache miss instead of waiting for the pricing model | Response time matters to users. A request that fetched its own rates could wait up to 3s on a hung call, and 7.5% of calls hung in testing. Reading the cache took about 11ms at p50, for both hits and misses |

### Known risks accepted

These estimates use the failure rate from one test run of 970 calls.

- **Higher model cost.** The worker makes about 520 calls a day even with no traffic, against about 345 if requests fetched on demand.
- **Short gaps in rates.** When the attempts at 180s and 270s both fail, about 12 times a day, requests return `503` for up to 60s, because rates older than 5 minutes are never served.
- **Worker down means no rates.** Requests return `503` within 5 minutes of the worker stopping, and nothing alerts on this. A Compose healthcheck wouldn't help, because Compose doesn't act on it. Production should alert on `503` rates or on `rate_refresh_succeeded` logs stopping.
- **The 960 limit assumes** that nothing else uses the token and that Redis keeps the gate. A Redis wipe could allow one extra call.

## Logging

| # | Date | Status | Decision | Why |
|---|---|---|---|---|
| 25 | 2026-11-02 | Accepted | Log one JSON line per request with lograge, including `request_id`, `error_code` and the raw `params` | Makes requests searchable and tied to the `X-Request-Id` a client receives. Fields can be extracted from `params` by a log parser downstream, so the app doesn't select them. Callers can put arbitrary text in `params`, so a parser shouldn't trust those values |
| 26 | 2026-11-02 | Accepted | Don't log throttled requests | A client over the limit could flood the logs. A future option is logging an IP only after a number of throttles |
| 27 | 2026-11-02 | Accepted | Log app events through `StructuredLog`, with a `request_id` on request errors and a `refresh_id` on each worker attempt | Every line has the same fields. A `500` can be traced from the client's `X-Request-Id`, and all of a refresh's lines can be found together, as the worker has no request ID |

## Response times

Moving fetching to the worker keeps the pricing model out of the request path, so its speed and failures don't reach users as delays.

| Request | p50 | p95 | Max |
|---|---|---|---|
| Cache hit (`200`) | 11.5ms | 14.6ms | 40.7ms |
| Cache miss (`503`) | 10.9ms | 15.5ms | 57.9ms |

Measured over 100 sequential requests each, on a local Compose stack in development mode, so these show the scale rather than a production figure.

If requests fetched on a miss, the request triggering a refresh would wait for the model. About 7.5% of calls hung in testing, and each would hold that request for up to 3s (the 1s connect and 2s read timeouts). Other requests would either queue behind it or make calls of their own.

## Scaling limits

The brief only asks for rates across a fixed set of 36 combinations, at 10,000 requests a day. It doesn't mention an arbitrary or growing number of hotels, so one batch is enough for now.

The worker already handles any amount of request traffic, since requests never call the model. What limits growth is the catalogue. The API documents no batch size limit, and only 36 items have been tested. If the catalogue outgrew one request, batches would need splitting, and each batch is another call:

| Batches per window | Calls/day if refreshed only at expiry, every call succeeding | Same, at the measured 1-in-6 failure rate | Within 1,000? |
|---|---|---|---|
| 1 | 288 | about 345 | Yes |
| 2 | 576 | about 690 | Yes |
| 3 | 864 | about 1,035 | No |

Those are minimums. Refreshing early, as the worker does to hide failures, costs more, so splitting buys about one doubling at best. Beyond that, the options are a higher quota, more tokens, or fetching only the combinations in demand. Splitting also needs one cache entry and one gate per batch, so that a failed batch doesn't affect the others.

## Deliberately left out

| Option | Why not |
|---|---|
| A database | The service has no tables, and rates only live for 5 minutes |
| Sidekiq or another scheduler | One periodic job doesn't need them. See decision 21 |
| A daily call counter | The gate already caps calls at 960 a day, without needing to know when the quota resets |
| Serving old rates during an outage | Rates must be no older than 5 minutes (decision 7) |
| Swagger UI | The YAML file is enough for one endpoint |
| factory_bot | There are no models to build |
| Git hooks | CI runs the tests and lint |

## Change log

### 2026-11-02: Document the worker trade-offs and logging

- Expanded the README's trade-offs of using a worker over fetching during the request.
- Added a logging section to the README, and the Docker requirements to its setup section.
- Corrected rows in the pricing model behaviour table that still described requests calling the API.

### 2026-11-02: Structure app logs and add a refresh ID

- Added `StructuredLog`, used by every app log call, which adds the event name, timestamp and any current ID (decision 27).
- Added `Current`, set by a `before_action` for `request_id` and around each worker attempt for `refresh_id`.
- `cache_unavailable` and `unhandled_error` are now JSON events rather than plain strings.

### 2026-11-02: Log requests as JSON with lograge

- Added `lograge`, replacing Rails' multi-line request logs with one JSON line per request (decision 25). All of it is configured in the initializer, with no logging code in controllers. It reads the error code from the response body on failed requests.
- Exposed `X-Request-Id` through CORS, so browser clients can quote it when reporting a problem.
- Removed production's `log_tags` and its `Logger::Formatter`. Both prefixed each line with text that made it invalid JSON. The request ID is now a field in the JSON.

### 2026-10-31: Finish the documentation

- Rewrote the README with the design, a summary of the key decisions, its trade-offs, the API and how to run everything. This log is now the audit record behind it.
- Recorded response times and the decision to fail fast on a cache miss (decision 24).
- Updated the scaling section for the worker design, and marked decisions 11 and 14 as superseded.

### 2026-10-31: Generate API docs with openapi-ruby

- Added `openapi-ruby` in the development and test groups only, because docs are generated from specs (decision 15). `openapi/public_api.yaml` is the committed output.
- `spec/openapi/pricing_spec.rb` documents the endpoint and exercises every response against its schema. Components live in `spec/api_components`, since the gem isn't installed in production.
- The error `code` values and the query parameter values come from `ErrorCodes::REGISTRY` and `Pricing::IndexRequest`, so they can't drift from the code. A spec fails if a registered error code has no documented response.
- Turned off the gem's automatic `400` response, because this API never returns one.
- Did not mount the gem's engine or Swagger UI. The YAML file is enough for one endpoint, and this adds no routes to the running app.
- CI regenerates the docs and fails if the committed file differs.

### 2026-10-31: Add CORS and explicit UTC

- Added `rack-cors` with `origins "*"` until real origins are known. This should be narrowed before production if browsers will call the API directly.
- Allowed only `GET`, `HEAD` and `OPTIONS`, because the API has no write endpoints.
- Exposed `Retry-After` so browsers can read it on a `429`.
- Set the time zone and Active Record's default to UTC explicitly. Both were already the Rails default, so behaviour doesn't change.

### 2026-10-31: Throttle requests with rack-attack

- Added `rack-attack`, limiting each IP to 300 requests a minute. Going over returns `429 rate_limited` with `Retry-After`, in the standard error format.
- This protects the app and Redis, not the upstream quota, which traffic can no longer affect. The limit is a judgement call: 10,000 requests a day averages about 7 a minute, so this leaves wide room for peaks or for many users behind one IP.
- It counts `request.ip`, so behind a proxy, Rails must be configured to trust that proxy, or all clients would share one limit.
- Gave rack-attack its own Redis store. With `Rails.cache`, its middleware would hit the re-raised errors from decision 12 and return a raw `500` during an outage. Its store fails open, so requests reach the controller and get the standard `503`.
- Added `ApiError#to_h`, so the middleware and controller share one error format.

### 2026-10-31: Refresh rates in a worker

- Added `Pricing::RateRefresher` and `bin/rate_refresher`, which checks every 5s and refreshes once rates reach 180s of age (decision 21).
- Added the 90s gate, an atomic `Rails.cache` write that allows one call per period. This caps usage at 960 calls a day (decision 20). If Redis can't be reached, no call is made.
- `PricingService` now only reads the cache, so requests can never call the API. A miss returns `503 pricing_unavailable`.
- Renamed `pricing_upstream_error` to `rate_not_available`, as its only remaining use is a missing rate. Removed `pricing_upstream_timeout`, because requests no longer make calls that can time out.
- Added a `rate-refresher` Compose service. In development it also logs to stdout, so `docker compose logs` shows it.
- Added specs that simulate a full day of ticks to check the 960 limit, and that 1,000 requests with an empty cache make no calls.
- Extended CI's endpoint check to 70 attempts over about 3.5 minutes. The first rates can now take up to 90s after a failed attempt.

### 2026-10-31: Cache rates in a snapshot

- Added `Pricing::RateSnapshot`, which holds all rates under one cache key (decision 5), each with its own `fetched_at`, so a row kept from an earlier fetch expires on its own schedule (decision 17).
- The entry expires 5 minutes after the latest `fetched_at`, which is taken before the call is sent because the API gives no timestamps (decision 7). Reads also check each rate's age, so a rate can't outlive the limit if a TTL is ever wrong.
- Moved fetching and row validation from `PricingService` to `Pricing::RateFetcher`, so the worker can use them.
- A response with no valid rates is now an error and leaves the stored snapshot in place, rather than replacing good rates with nothing.
- For now, a cache miss still fetches during the request, so this commit works on its own. The worker commit removes that (decision 20). Until then, the quota guarantee does not hold.

### 2026-10-31: Add Redis as the cache store

- Added the `redis` gem and a `redis` Compose service, and set `Rails.cache` to use it in every environment except test (decision 6). `REDIS_URL` is set in Compose.
- The store's `error_handler` now re-raises (decision 12), and `ApplicationController` turns Redis errors into `503 pricing_unavailable`. The handler is in `config/application.rb` because Rails builds the cache store before `config/initializers` runs.
- Specs use `memory_store`, so they run without a Redis server. The handler's behaviour is tested against an unreachable Redis.
- Nothing reads or writes the cache yet.
- Logged the worker design as accepted (decisions 20 to 23), which replaces the lock and failure-key options discussed earlier.

### 2026-10-31: Fetch rates in batches with a reliable client

- Moved `RateApiClient` to `app/clients/`, keeping its name. A `Clients::` prefix would need an `app/clients/clients/` directory, which adds nothing for one client.
- The client now has a 1s connect and 2s read timeout (decision 13), and logs each call as JSON with its duration and status. It raises `TimeoutError`, `QuotaExceededError` or `Error`.
- `PricingService` now requests all 36 combinations in one call (decision 5). Not cached yet, so each request still makes a call.
- Added `504 pricing_upstream_timeout` and `503 pricing_unavailable`. Invalid JSON from upstream now returns `502` instead of `500`.
- `rate` is now always returned as an integer, because the API returns integers but documents strings. This changes the response type from what the scaffold's tests implied.
- Invalid rows are logged and skipped, so one bad row doesn't take down the other 35 rates. Asking for a skipped combination returns `502`.
- Missing, duplicate and unrequested rows are now logged and handled as decisions 17 to 19 describe.
- Added WebMock so the client and request specs run against stubbed HTTP. The scaffold's mocks hid its lost-error-message bug by returning a Hash where the real client returns a String.

### 2026-10-31: Parse query parameters with a request model

- Added `json_model_rb`, `ApplicationRequestModel` and `Pricing::IndexRequest`, which replace the controller's hand-written validation and are now the only list of valid values.
- Added `parse_request` to `ApplicationController`. It reads `request.query_parameters` directly, because this endpoint has no request body (decision 10).
- Added `ApplicationRequestModel.errors_for`. `Dry::Struct` stops at the first problem and its messages expose internals, so this checks each declared field and keeps reporting every problem in plain wording.
- Unknown query parameters now return `422 validation_failed`, because the base request model is strict. This catches typos, but clients that add extras, such as a cache-busting parameter, also get an error.

### 2026-10-31: Serialize responses with Alba

- Added `alba` and `Pricing::RateSerializer`, and the pricing response now renders through it. The response body is unchanged.
- Set Alba's backend to `active_support`, so JSON generation stays consistent with the rest of Rails and adds no JSON gem.
- Error responses stay as a hash in `ApplicationController`, because they already have one central place to render.

### 2026-10-31: Standardize API errors

- Added `ErrorCodes::REGISTRY` and `ApiError`, with one `rescue_from` in `ApplicationController` rendering `{ "error": { "code", "message", "details" } }`.
- Invalid parameters now return `422 validation_failed` instead of `400`, and `details` lists every bad field at once rather than only the first.
- Upstream failures now return `502 pricing_upstream_error` instead of `400`, because they aren't the client's fault. The upstream message is no longer passed through.
- Fixed three scaffold bugs: upstream error messages were lost because `rate.body["error"]` ran on a String, a missing rate returned `200 {"rate": null}`, and unexpected exceptions returned Rails' default error page.
- Unexpected exceptions now return `500 internal_error` and log the detail on the server only.
- Removed `valid?` and `errors` from `BaseService`, since services now raise.
- Timeout and availability codes will arrive with the code that raises them. Invalid JSON from upstream currently returns `500`, until the client change handles it as an upstream error.

### 2026-10-31: Add Rubocop

- Added `rubocop-rails-omakase` and `.rubocop.yml`. The repository had no Rubocop config, and this is the Rails default ruleset with a small set of style rules.
- Fixed the existing style offenses, mostly quote style. No behaviour changes.
- Added a lint step to CI before the tests, so style failures stop the run early.
- Pinned `json` below 3. Rubocop added it to the lockfile and Bundler chose 3.1.0, which breaks JSON rendering on Rails 7.1 by rejecting its `quirks_mode` option. The specs caught this before commit.

### 2026-10-30: Replace Minitest with RSpec

- Added `rspec-rails` and generated `.rspec` and the `spec/` helpers.
- Ported the controller tests to `spec/requests/api/v1/pricing_spec.rb`, with one behaviour per example. They still assert the scaffold's behaviour, and later commits change that alongside the code.
- Removed `test/`, and updated CI and the README to run `bundle exec rspec`.
- Pass `RAILS_ENV=test` on the command that runs the specs. The Dockerfile sets it to `development`, which `bin/rails test` overrode but `rspec` doesn't, and `rails_helper` keeps its generated default.
- Did not add factory_bot, because there are no models to build.
- This makes openapi-ruby possible (decision 15), since it generates docs from request specs.

### 2026-10-30: Repository setup

- Renamed `README.md` to `spec.md`, unchanged.
- Added a new `README.md` and this file.
- Added `docker-compose.example.yml` with a token placeholder.
- Gitignored and untracked `docker-compose.yml`. The local copy holds the real token.
- Removed the hardcoded token default from `lib/rate_api_client.rb`.
- Updated `.github/workflows/ci.yml` to create the compose file from the example.
