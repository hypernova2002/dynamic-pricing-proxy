# Decisions and Changes

The running record of what was decided, why, and what changed. Add to it with every change.

## Reviewing this work

The original assignment is commit `19fb148` (`19fb14848a0683f3114b4684b089dc3b6ccd42d7`, "Add customer-data-pipeline data engineer assignment"). Everything after it is this solution:

```bash
git log --reverse 19fb148..HEAD
git diff 19fb148..HEAD
```

**Status values:** Accepted (agreed and in force), Proposed (awaiting sign-off), Deviation (a deliberate departure from the conventions).

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
| Consecutive failures | At most 3 in the run | Failures are short-lived, so the next request usually succeeds |
| Quota exceeded | `429 {"error": "Rate limit exceeded (1000/day)"}` | Treat as unavailable and return 503 |
| Quota accounting | The 429 arrived after 970 batch calls plus 30 bad-value calls, with 30 bad-token calls also sent. So 500s and hangs count against the quota, and bad tokens appear not to | Failed calls spend quota. See the known risks below |
| Bad token | `401 {"error": "Unauthorized"}` | Log as a configuration error and return 502. Never pass it to the client |
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
| 8 | 2026-10-30 | Accepted | Use conventions-format errors: `{ "error": { "code", "message", "details" } }`, from a central registry | Requested by the author. Replaces the scaffold's `{ "error": "message" }` and its tests |
| 9 | 2026-10-30 | Accepted | Use RSpec instead of Minitest, and add Alba, rack-attack and json_model_rb | Requested by the author, matching the conventions |
| 10 | 2026-10-30 | Accepted | Use a json_model_rb request model for the pricing query parameters | Requested by the author. The conventions describe request models for bodies, so this extends the pattern to a GET |
| 11 | 2026-10-30 | Accepted | No distributed lock. Cache only valid results through `Rails.cache.fetch` | Calls take milliseconds at 0.12 requests a second, so concurrent misses are rare. Concurrent fetches may overwrite each other, but each result is still fresh |
| 12 | 2026-10-30 | Accepted | Make Redis errors raise through the cache store's `error_handler`, returning 503 | `Rails.cache` otherwise reports Redis errors as cache misses, and each miss would spend quota |
| 13 | 2026-10-30 | Accepted | Set a 1s connect and 2s read timeout on upstream calls | Hangs lasted over 120s in testing, while successful calls took 43ms at most |
| 14 | 2026-10-30 | Accepted | No retries, failure backoff or daily call counter | Chosen by the author for simplicity. The next request after a failure simply tries again |
| 15 | 2026-10-30 | Accepted | Generate API docs with openapi-ruby from the RSpec request specs | Moving to RSpec (decision 9) makes this possible. It matches the conventions and keeps the docs in sync with the tests |
| 16 | 2026-10-30 | Accepted | Update this document in every commit | Requested by the author, so each commit carries its own reasoning |
| 17 | 2026-10-31 | Accepted | A missing row returns `502` for that combination only, and the valid rows are still used | One bad row shouldn't block the other 35 prices. Once cached, this costs no extra quota, but the combination can fail for up to 5 minutes |
| 18 | 2026-10-31 | Accepted | Duplicate rows overwrite, so the last one wins, and are logged | Rows have no identifiers to tell them apart, and rates vary per call, so duplicates may disagree |
| 19 | 2026-10-31 | Accepted | Rows that weren't requested are ignored and logged | With no identifiers they can't be matched to anything, so they shouldn't be cached |
| 20 | 2026-10-31 | Accepted | Never let traffic decide how often the API is called: a worker refreshes the cache, requests only read it, and one Redis key allows at most one call every 90s | The author requires that the quota is never hit, whatever the traffic. This caps calls at 960 a day. Replaces decisions 11 and 14 |
| 21 | 2026-10-31 | Accepted | Run the worker as a loop in `bin/rate_refresher`, refreshing once rates reach 180s of age | What to do depends on the age of the rates and the last attempt, not the time of day. Cron can only run once a minute, and rake adds nothing to a process that never exits |
| 22 | 2026-10-31 | Accepted | No quick retry. The next attempt comes 90s later | A quick retry would need a 180s gate to keep the 960 limit. It gives no benefit while rates are still valid, and spaced attempts cope better with a problem that lasts more than a moment |
| 23 | 2026-10-31 | Accepted | Log failed refresh attempts at `info` | There are no quick retries to keep quiet, so each failure is worth seeing at the production default level |

### Known risks accepted

- **Failed refreshes reach users.** About 1 call in 6 fails, so about 1 in 6 refreshes returns an error to the request that triggered it. That is roughly 57 errors a day at 10,000 requests, and the next request tries again.
- **Normal quota use rises slightly.** Failed calls spend quota, so healthy use is about 345 calls a day rather than 288.
- **A long outage can exhaust the quota.** Every request during an outage makes an upstream call, so 1,000 requests would use up the day's quota. Rates then stay unavailable after the outage ends, until the quota resets.

## Scaling limits

The brief only asks for rates across a fixed set of 36 combinations, at 10,000 requests a day. It doesn't mention an arbitrary or growing number of hotels, so one batch is enough for this assignment.

One batch per 5-minute window won't hold if the catalogue grows:

| Batches per window | Calls/day if every call succeeds | Calls/day at the measured 1-in-6 failure rate, retried until success | Within 1,000? |
|---|---|---|---|
| 1 | 288 | about 345 | Yes |
| 2 | 576 | about 690 | Yes |
| 3 | 864 | about 1,035 | No, once failures are counted |

Splitting batches therefore only helps up to a point. The quota allows about 2 batches per window, so capacity is about 2 × the largest batch the API accepts. That batch limit is unknown. Beyond it, the options are a higher quota, more tokens, or fetching only the combinations in demand.

**Expected long-term design:** a worker process refreshes the cache, and requests only read from it.

- Users no longer see failed refreshes, because retries happen in the worker while the current rates are still valid.
- Refreshing early costs quota. Refreshing every 4 minutes takes 360 windows a day rather than 288, which lowers the numbers above.
- Only one scheduler may run, because the token's quota is shared.
- Splitting needs one cache entry per batch, so that one failed batch doesn't invalidate the others.

**Decision for now:** keep one batch, as the brief's fixed scope doesn't need more. Whether to move to a worker now is under review (decision 20).

## Convention review

Compared against `~/.claude/CLAUDE.md` and `~/.claude/rules/rails-conventions.md` on 2026-10-30.

### Changes the review makes to the design

| Convention | Change |
|---|---|
| API clients live in `app/clients/` | Move `RateApiClient` out of `lib/` |
| One error code registry, custom error classes, a single `rescue_from` | Add `app/errors/error_codes.rb` and `ApiError` |
| YARD comments where behaviour isn't obvious | Add to the new service and client only |
| Every project has a `rack-cors` initializer | Add it, with `origins '*'` until real origins are known |
| Rubocop and CI lint | Add `.rubocop.yml`, and add Rubocop to CI |
| Timezone defaults to UTC | Set it explicitly |

### Deliberate deviations

| Convention | Deviation | Why |
|---|---|---|
| Compose has `api`, `db` and `yard` services | Keep `interview-dev`, and add no `db` or `yard` | The brief's commands use that name, nothing uses a database, and YARD comments don't need a server |
| PostgreSQL | No Postgres | The service has no tables |
| Lefthook git hooks | Not added | Decided by the author. CI runs the tests and lint instead |
| Commit attribution from the tooling | No co-author lines | `CLAUDE.md` says not to co-author commits, and that takes precedence |

### Already aligned or not applicable

- **Aligned:** Docker-only development, no `.env` files, feature branch workflow, external services stubbed in tests, and service objects for orchestration.
- **Not applicable:** Pagy and Ransack (no list endpoints), uids (no exposed records), migrations and background jobs (none needed).

## Change log

### 2026-10-31: Add Redis as the cache store

- Added the `redis` gem and a `redis` Compose service, and set `Rails.cache` to use it in every environment except test (decision 6). `REDIS_URL` is set in Compose.
- The store's `error_handler` now re-raises (decision 12), and `ApplicationController` turns Redis errors into `503 pricing_unavailable`. The handler is in `config/application.rb` because Rails builds the cache store before `config/initializers` runs.
- Specs use `memory_store`, so they run without a Redis server. The handler's behaviour is tested against an unreachable Redis.
- Nothing reads or writes the cache yet.
- Logged the worker design as accepted (decisions 20 to 23), which replaces the lock and failure-key options discussed earlier.

### 2026-10-31: Fetch rates in batches with a reliable client

- Moved `RateApiClient` to `app/clients/`, keeping its name. The conventions' `Clients::` prefix would need an `app/clients/clients/` directory, which adds nothing for one client.
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
- Unknown query parameters now return `422 validation_failed`, because the conventions' strict base model rejects them. Clients that add extras, such as a cache-busting parameter, will get an error.

### 2026-10-31: Serialize responses with Alba

- Added `alba` and `Pricing::RateSerializer`, and the pricing response now renders through it. The response body is unchanged.
- Set Alba's backend to `active_support`, so JSON generation stays consistent with the rest of Rails and adds no JSON gem.
- Error responses stay as a hash in `ApplicationController`, because the conventions already give them one central place to render.

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
