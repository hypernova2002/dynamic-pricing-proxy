# Dynamic Pricing Proxy

A Rails API that sits in front of Tripla's dynamic pricing model and serves hotel room rates while staying within the model's limit of 1,000 calls per day.

**Status: in progress.** The endpoint still calls the pricing model on every request. Caching and failure handling are designed but not built yet.

- [spec.md](spec.md): the original assignment brief
- [DECISIONS.md](DECISIONS.md): design decisions, convention review and change log

## Setup

Everything runs in Docker. You don't need Ruby installed on your machine.

1. Create your local compose file. It is gitignored, so your token stays out of the repository:

   ```bash
   cp docker-compose.example.yml docker-compose.yml
   ```

2. In `docker-compose.yml`, replace `REPLACE_WITH_RATE_API_TOKEN` with the token from the [rate-api documentation](https://hub.docker.com/r/tripladev/rate-api). The app won't start without `RATE_API_TOKEN`.

## Run

```bash
docker compose up -d --build

curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'
```

## Test

```bash
# Full suite
docker compose exec -e RAILS_ENV=test interview-dev bundle exec rspec

# One file
docker compose exec -e RAILS_ENV=test interview-dev bundle exec rspec spec/requests/api/v1/pricing_spec.rb
```

## Lint

```bash
docker compose exec interview-dev bundle exec rubocop
```

## CI

CI builds `docker-compose.yml` from the example file, so the repository needs a `RATE_API_TOKEN` Actions secret.

## AI assistance

This solution is being developed with Claude Code. So far it has been used to review the brief and API documentation, propose the design, compare it against the project's conventions, and set up the repository files. All AI-assisted work is reviewed by the author, and this section will be updated as the work continues.
