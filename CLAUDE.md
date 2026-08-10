# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal Flutter web app ("Borsa Takip") for tracking stocks/crypto (BIST,
US markets, crypto) via Yahoo Finance data: candlestick charts at multiple
intervals, a monthly-low table for a chosen date range, and a watchlist that
gets checked once a day for new intra-month lows, surfaced as a paginated
notification feed.

Two independent Dart projects, run as two separate local processes:

- `proxy_server/` — a Dart `shelf` HTTP server (console app, not a Flutter
  project). It exists solely because Yahoo Finance's chart/search endpoints
  don't send CORS headers, so the Flutter **web** build cannot call them
  directly from the browser. It also proxies CoinGecko for the crypto
  preset list, and owns all persisted state (watchlist, notifications).
- `borsa_takip/` — the Flutter web frontend. For market/watchlist/
  notification data it only ever talks to `proxy_server` (`_baseUrl` in
  `lib/services/market_api.dart`, defaults to `http://localhost:8787`,
  overridable via `--dart-define=API_BASE_URL=...` for deployed builds),
  never to Yahoo/CoinGecko directly. It talks directly to Supabase only for
  auth (sign-up/sign-in/session), via `supabase_flutter` — never for
  watchlist/notification data, which stays behind the proxy.

Both must be running simultaneously for the app to work.

## Commands

Dart/Flutter SDK note: on this machine `flutter`/`dart` resolve to
`C:\src\flutter\bin\...`, and that install has no `git` on PATH, which makes
`dart.bat`'s wrapper print a harmless "Unable to determine engine version"
warning before every command. If `dart`/`flutter` aren't on PATH at all,
call `C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe` /
`C:\src\flutter\bin\flutter.bat` directly instead of fighting PATH.

Backend (`proxy_server/`):
```powershell
dart pub get
dart run bin/server.dart          # serves on :8787 (override with $env:PORT)
dart analyze .
```

Frontend (`borsa_takip/`):
```powershell
flutter pub get
flutter run -d web-server --web-port=5000
dart analyze lib
flutter test                      # runs test/widget_test.dart
```
`-d chrome` reliably fails to launch in this environment ("Failed to launch
browser after 3 tries") — always use `-d web-server` and open
`http://localhost:5000` in a browser separately.

There is no combined build/lint/test script — the two projects are analyzed
and tested independently as shown above.

### Windows/PowerShell gotchas hit repeatedly in this repo

- `flutter run -d chrome` sometimes fails on restart with "Flutter failed to
  delete a directory at build\flutter_assets" (stale lock). Fix: stop the
  process, `Remove-Item build -Recurse -Force`, then rerun.
- `flutter analyze` can crash the LSP-based analysis server in this
  environment (`FormatException` in `lsp_byte_stream_channel.dart`). Use
  `dart analyze lib` (or `dart analyze .` for proxy_server) instead — it's
  the same analyzer, just without the LSP transport.
- After editing PowerShell text with `Get-Content | -replace | Set-Content`,
  Turkish characters (ü, ı, ş, ğ, ö, ç) can get corrupted (mojibake) because
  `Get-Content` doesn't default to UTF-8 on this system. Prefer the Edit/Write
  tools for any file containing Turkish text; if you must shell out, pass
  `-Encoding utf8` explicitly on both read and write.
- If `flutter run -d web-server` was left running and its browser tab/window
  gets closed, a *new* tab pointing at `localhost:5000` connects to the same
  orphaned DWDS debug session and the page hangs blank forever (module
  loader logs "Injecting <script> tag" on a loop, never reaches "Starting
  application from main method"). Fix: kill the `flutter run` process and
  start it fresh, then open exactly one new tab against it.

## Architecture

### Backend (`proxy_server`)

Single-file router (`bin/server.dart`) wired to four `lib/` modules:

- `yahoo_client.dart` — `fetchChart()` is the one shared function that hits
  Yahoo's `/v8/finance/chart/{symbol}` endpoint and parses OHLC candles.
  Both `/api/candles` and the monthly-low checker call it — don't duplicate
  Yahoo-parsing logic elsewhere.
- `store.dart` — `WatchlistStore` and `NotificationStore`, persisted in a
  Supabase Postgres project via `supabase_client.dart` (a minimal PostgREST
  wrapper, not the official SDK). Multi-tenant: every method takes a
  `userId` and queries Supabase filtered to that user (no in-memory cache —
  a single-user leftover from the pre-auth era, removed once data became
  per-user). `symbolsFor(userId)` seeds a user's watchlist with 8 default
  symbols the first time it's empty. `WatchlistStore.allRows()` returns
  every user's `(user_id, symbol)` pairs for the background checker.
  Table schema: `proxy_server/supabase_schema.sql` +
  `supabase_schema_auth.sql` (run once each, in order, in the Supabase SQL
  Editor — the second adds `user_id` and RLS). Requires `SUPABASE_URL` and
  `SUPABASE_SERVICE_KEY` env vars (see `proxy_server/.env.example`; locally
  read from a gitignored `proxy_server/.env` via `lib/env.dart`, in
  production set directly in Render). One-off local→Supabase data
  migration: `dart run bin/migrate_to_supabase.dart` (idempotent, reads the
  old `proxy_server/data/*.json` files if present).
- Auth: `_authenticate()` in `bin/server.dart` reads the `Authorization:
  Bearer <token>` header and validates it against Supabase's
  `/auth/v1/user` endpoint (one HTTP call, not local JWT verification —
  kept consistent with the rest of the codebase, which has no JWT
  dependency). Guards every `/api/watchlist*` and `/api/notifications*`
  handler; returns 401 if missing/invalid. `/api/search` and
  `/api/candles` stay public (no per-user data).
- `monthly_low_checker.dart` — `MonthlyLowChecker.checkAll()` groups all
  users' watchlist rows by symbol (so a symbol watched by multiple users is
  fetched from Yahoo only once), walks the distinct symbols sequentially
  (300ms delay between each to avoid Yahoo rate-limiting), and for each
  compares today's low against the lowest of all *prior* days this month.
  If today set a new low, every user watching that symbol gets their own
  notification (deduped by `userId+symbol+date`).
- `preset_lists.dart` / `coingecko_client.dart` — static curated symbol
  lists (`bist100Symbols`, `usPopular100Symbols`) and a live CoinGecko
  top-N-by-market-cap fetch, used by `/api/watchlist/bulk-add`.

`GET /health` — plain `200 "ok"`, no auth, no dependencies. Exists solely
as a target for Render's health check; `/api/*` routes are the wrong choice
since the watchlist/notifications ones now require auth (see below) and
Render marking the service unhealthy over 401s hangs a deploy for ~15
minutes before failing it.

Key endpoints (all under `/api/`, CORS-open, JSON in/out):
`search`, `candles` (params: `symbol,start,end,interval` where interval is
one of `1d/1wk/1mo/3mo/12mo` — `12mo` doesn't exist in Yahoo and is
synthesized server-side by grouping `1mo` candles in chunks of 12),
`watchlist` (GET/add/remove/bulk-add), `notifications` (paginated, 100/page,
newest first), `notifications/check-now` (fire-and-forget — does NOT await
the full scan, since a large watchlist can take minutes; guarded by a
module-level `_checkInProgress` flag against overlapping runs). All
`watchlist*`/`notifications*` endpoints require `Authorization: Bearer
<token>` (see Auth above); `search`/`candles`/`health` don't.

`main()` also runs `checker.checkAll()` once at startup and then on a
`Timer.periodic(Duration(hours: 24))` — this only fires while the process
stays alive, there's no OS-level scheduler.

### Frontend (`borsa_takip`)

`main.dart` → `AuthGate` (listens to `Supabase.instance.client.auth
.onAuthStateChange`) shows `LoginScreen` (email/password + Google OAuth via
`supabase_flutter`) when signed out, else `RootShell`. `RootShell` holds an
`IndexedStack` of two independent tab screens behind a bottom
`NavigationBar`: `HomeScreen` (chart/table) and `NotificationsScreen`
(watchlist management + notification feed). They don't share state beyond
both owning their own `MarketApi()` instance. `services/supabase_config.dart`
holds the (non-secret) Supabase URL + anon/publishable key, hardcoded as
`String.fromEnvironment` defaults — same pattern as `API_BASE_URL`.

`services/market_api.dart` is the only HTTP boundary — every screen goes
through it, never calls `http` directly. Every request attaches
`Authorization: Bearer <current Supabase access token>` (see `_authHeaders`)
so the backend can scope watchlist/notifications to the signed-in user. All
failures surface as `ApiException` with a Turkish message (including a
specific one for "proxy not running").

`widgets/candlestick_chart.dart` renders with a `CustomPainter`
(`_CandlestickPainter`), not a charting package — there was a real bug here
(canvas/texture width limit around ~8000px silently truncated long daily
ranges) fixed by computing `slotWidth` from `LayoutBuilder`'s
`constraints.maxWidth / candles.length` (clamped `[1.5, 46]`) so the whole
range always fits without horizontal scroll, thinning candles as needed
instead of scrolling.

Candle "period" labels (e.g. `Q3 25`, `2024-2025`, `31.07.25`) are formatted
server-side per interval — the frontend just displays `candle.period`
as-is, it does no date formatting of its own for chart data.

## Deployment

- `borsa_takip` → **GitHub Pages** (`https://ercinnn.github.io/borsa/`), via
  `.github/workflows/deploy-pages.yml`: builds on every push to `main` that
  touches `borsa_takip/**`, with `--base-href /borsa/` and
  `--dart-define=API_BASE_URL=<repo var>`. The repo variable `API_BASE_URL`
  (Settings → Secrets and variables → Actions → Variables) must point at the
  Render URL below.
- `proxy_server` → **Render** (`https://borsa-proxy.onrender.com`), free web
  service defined in `render.yaml` (Docker, AOT-compiled via the
  `proxy_server/Dockerfile`). Needs `SUPABASE_URL` and `SUPABASE_SERVICE_KEY`
  set as env vars directly in the Render dashboard (Environment tab) —
  `render.yaml` only declares the *names* (`sync: false`), never the values.
  Free tier spins down after ~15 min idle; first request after that takes
  30–50s.
- **Auto-deploy is unreliable in practice**: Render's service has
  Auto-Deploy set to "On Commit", but pushes to `main` have repeatedly *not*
  triggered a new build. Always check the service's Events page after
  pushing a `proxy_server` change, and use Manual Deploy → "Deploy latest
  commit" if nothing started within a minute or two.
- **`render.yaml` field edits don't sync to an existing service.** Changing
  `healthCheckPath` (or other blueprint fields) in `render.yaml` and pushing
  does not update the already-created Render service's settings — it must
  also be edited by hand in Settings → Health Checks. This bit us for real:
  the health check was still hitting `/api/watchlist` after that route
  started requiring auth, so every deploy sat "waiting for health check" for
  ~15 minutes and then failed (and a stale cached image from an earlier
  build had been silently serving as "live" in the meantime, running old
  pre-auth code with no `/health` route at all). Whenever a blueprint field
  actually needs to change, edit it in both places.

## Known rough edges

- BIST100/US-popular-100 preset lists are hand-curated snapshots, not a
  live index feed (Yahoo's actual "most active" screener needs
  cookie/crumb auth this proxy doesn't implement) — expect occasional stale
  or wrong tickers; the checker just skips symbols that fail to fetch.
- `git` is not installed on the primary dev machine by default; when it is
  installed via winget mid-session, a *new* shell is needed before `git`
  resolves on PATH (the invoking shell keeps its stale PATH).
