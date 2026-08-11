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

Android APK (same `borsa_takip/` project, `android/` platform folder added
alongside `web/`):
```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://borsa-proxy.onrender.com
```
Output: `build/app/outputs/flutter-apk/app-release.apk`, sideload directly
(no Play Store, no signing keystore set up — release build type falls back
to the Flutter template's debug signing config, which is fine for personal
installs but not for Play Store distribution). Google Sign-In is hidden on
non-web platforms (`kIsWeb` check in `login_screen.dart`) since
`signInWithOAuth`'s `redirectTo: Uri.base.toString()` is a web-only concept;
email/password auth works identically on Android. `AndroidManifest.xml`
needs its own explicit `<uses-permission android:name=
"android.permission.INTERNET"/>` (the Flutter template only grants it in
the debug-build manifest, not main) — already added, but worth remembering
if `flutter create` ever regenerates that file.

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
  Yahoo-parsing logic elsewhere. `fetchDividends()` is a separate function in
  the same file (shares the `userAgent`/`YahooException` plumbing but issues
  its own request, since a plain OHLC request doesn't return dividend data):
  it hits the same chart endpoint with `events=div` and parses
  `chart.result[0].events.dividends` (keyed by timestamp, each value an
  `{amount, date}` pair) into a newest-first `List<DividendEvent>`. Bounded
  to the last 15 years rather than Yahoo's full history — BIST symbols'
  pre-2005 (pre-redenomination "eski TL") dividend amounts come back in the
  millions and would be misleading to show as-is. Has its own 6-hour cache
  (dividends change far less often than prices), keyed by symbol only and
  shared between `/api/dividends` and the portfolio dividend-income
  calculation below.
- `store.dart` — `WatchlistStore`, `NotificationStore`, `FavoritesStore`,
  `TrackedSymbolStore`, `TechnicalWatchlistStore`, `DividendWatchlistStore`,
  all persisted in a Supabase Postgres project via
  `supabase_client.dart` (a minimal PostgREST wrapper, not the official
  SDK). Multi-tenant: every method takes a `userId` and queries Supabase
  filtered to that user (no in-memory cache — a single-user leftover from
  the pre-auth era, removed once data became per-user). `symbolsFor(userId)`
  seeds a user's watchlist with 8 default symbols the first time it's
  empty; `FavoritesStore` does **not** seed defaults (empty until the user
  adds some). `WatchlistStore.allRows()` returns every user's
  `(user_id, symbol)` pairs for the background checker. `FavoritesStore` is
  a deliberately separate concept from `WatchlistStore` — the watchlist
  drives the daily monthly-low notification checker, favorites are just a
  personal shortlist (Favoriler tab, the Grafik tab's quick-select bar, and
  the star toggle next to each watchlist symbol in Bildirimler); a symbol
  can be in either, both, or neither. `TrackedSymbolStore` holds one row per
  user (upserted, no history) for whichever symbol the Takip tab is
  currently showing. `TechnicalWatchlistStore` is the same shape as
  `FavoritesStore` again (own `technical_watchlist` table, no seeding, no
  notification side-effects) — it's just which symbols the Teknik tab
  currently analyzes; unrelated to `WatchlistStore`/`FavoritesStore`.
  `TechnicalWatchlistStore.allRows()` (mirrors `WatchlistStore.allRows()`)
  returns every user's `(user_id, symbol)` pairs; `fundamentals_cache.dart`'s
  background pre-sync job uses it to find the distinct symbol set to keep
  warm, since Temel Analiz reuses the same watchlist as Teknik.
  `PortfolioStore` backs the Portföy tab: one row per `(user_id, symbol)`
  (unique index, upserted via `resolution=merge-duplicates` — same pattern
  as `TrackedSymbolStore.setFor`), storing only `quantity`/`cost_basis`.
  Re-adding a symbol already held **overwrites** it rather than merging a
  weighted-average cost — a deliberate simplification (see
  `portfolio_summary.dart` below and `PortfolioScreen`'s doc comment).
  `DividendWatchlistStore` is the same shape as `TechnicalWatchlistStore`
  again (own `dividend_watchlist` table, no seeding, no notification
  side-effects) — it's just which symbols the Temettü tab shows; unrelated
  to `WatchlistStore`/`FavoritesStore`/`PortfolioStore`.
  Table schema: `proxy_server/supabase_schema.sql` +
  `supabase_schema_auth.sql` + `supabase_schema_favorites.sql` +
  `supabase_schema_technical.sql` + `supabase_schema_portfolio.sql` +
  `supabase_schema_dividends.sql` + `supabase_schema_fundamentals.sql` (run
  once each, in order, in the Supabase SQL Editor — the second adds
  `user_id` and RLS to the base tables, the third adds the `favorites` and
  `tracked_symbol` tables, the fourth adds `technical_watchlist`, the fifth
  adds `portfolio_holdings`, the sixth adds `dividend_watchlist`, the
  seventh adds `stocks`/`financial_statements`/`stock_scores` — see
  `fundamentals_cache.dart` below for why that last one's RLS pattern is
  the inverse of every table before it). Requires `SUPABASE_URL` and
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
  fetched from Yahoo only once), then walks the distinct symbols in
  concurrent batches of 4 (a 300ms pause between batches, not between every
  symbol, to avoid Yahoo rate-limiting while still being much faster than
  fully sequential), and for each compares today's low against the lowest
  of all *prior* days this month. If today set a new low, every user
  watching that symbol gets a notification — existing ones are checked and
  new ones inserted in one batched Supabase call per symbol (`existingUserIdsFor`
  / `NotificationStore.addAll`) rather than one round-trip per user.
  `yahoo_client.dart`'s `fetchChart()` also short-TTL-caches (2 min) by
  symbol+range+interval, shared with `/api/candles`.
- `preset_lists.dart` / `coingecko_client.dart` — static curated symbol
  lists (`bist200Symbols`, `usPopular200Symbols`, `cryptoFallbackSymbols`)
  and a live CoinGecko top-N-by-market-cap fetch, used by
  `/api/watchlist/bulk-add`. `bist200Symbols`/`usPopular200Symbols` are each
  exactly 200 entries (100 original + a second hand-picked 100/95 batch —
  see the in-file comment for the source); `cryptoFallbackSymbols` is only
  167 (deliberately short of 300 — it's a last-resort static backup for
  when CoinGecko is fully unreachable, not a guaranteed top-300, so it
  doesn't need to match the live count exactly). `fetchTopCryptoSymbols()`
  retries a few times with backoff on CoinGecko 429s, optionally
  authenticated via `COINGECKO_API_KEY` (`x-cg-demo-api-key` header, opt-in
  — see Deployment); if all retries fail and there's no cached result, the
  `crypto300` handler falls back to the static `cryptoFallbackSymbols` list
  rather than erroring.
- `technical_score_cache.dart` — `TechnicalScoreCache` powers the
  Bildirimler tab's "Puan Sıralaması" sub-tab: same batching pattern as
  `MonthlyLowChecker` (distinct symbols across all users' watchlists, 4 at a
  time, 300ms pause between batches), but computes each symbol's Teknik
  `TechnicalSummary.score` and holds it in an **in-memory** map (no
  Supabase table — not worth persisting, and Render's free tier spins down
  on idle anyway, wiping it on the next cold start regardless). Refreshed
  once at startup and every 4 hours via `Timer.periodic` in `bin/server.dart`
  (more often than `MonthlyLowChecker`'s 24h, since this cache is the only
  copy and gets wiped on every cold start). `/api/technical-scores` reads
  only from this cache (fast, no live Yahoo calls) and returns 404-free
  empty pages for symbols not yet scored — `pendingCount` in the response
  tells the frontend how many are still missing.
  `/api/technical-scores/refresh` fire-and-forget triggers a rescan, same
  `_checkInProgress`-style re-entrancy guard as `notifications/check-now`.
  Each refresh also diffs a symbol's previous cached score against the new
  one via `summarySignalForScore()` (exported from `technical_analysis.dart`
  so both files threshold identically); crossing a Güçlü Al/Al/Nötr/Sat/
  Güçlü Sat tier boundary writes a notification (via the same
  `NotificationStore`/table `MonthlyLowChecker` uses — no separate
  mechanism) to every user watching that symbol. Since the "previous" value
  only lives in this in-memory map, a cold start forgets it — a rare tier
  crossing can be missed right after a restart, but it can never
  double-notify (documented tradeoff, same reasoning as the cache itself).
  The frontend tells this notification type apart from a monthly-low one by
  checking for the fixed substring `'teknik puan kademesi değişti'` in the
  message (bkz. `notifications_screen.dart`'s `_NotificationTile
  ._isScoreChange`) rather than a new Supabase column — deliberately, to
  avoid a schema migration for what's ultimately just an icon/color choice.
- `technical_analysis.dart` — `computeTechnicalAnalysis()` powers the Teknik
  tab: Investing.com-style Pivot Points (classic formula off the *previous*
  day's H/L/C), Simple+Exponential moving averages for
  5/10/20/50/100/200 (row omitted/`null` if there isn't enough history yet —
  matters for recently-listed symbols), and eleven directional indicators
  (RSI(14), STOCH(9,6), STOCHRSI(14), MACD(12,26,9), ADX(14)+DI±, CCI(14),
  Highs/Lows(14), UO(7/14/28), ROC(12), Williams %R(14), Bull/Bear
  Power(13)) plus ATR(14) shown as a value only (volatility, not
  directional — excluded from every Buy/Sell tally). Each row's Al/Sat/Nötr
  threshold is the standard textbook convention for that indicator (not a
  reverse-engineering of Investing.com's undisclosed algorithm — results
  track it directionally but won't match exactly). The three summary boxes
  (moving averages / indicators / overall) are a simple vote count — `score
  = (buy - sell) / total`, thresholded into Güçlü Al/Al/Nötr/Sat/Güçlü Sat —
  our own aggregation, again not Investing.com's. The same vote count also
  produces `TechnicalSummary.score` (0-100 via `_scoreOf`, 50 = neutral) —
  this is the "Yorum (X/100)" button's X in `technical_screen.dart`, which
  opens a dialog with a rule-based Turkish commentary paragraph
  (`_generateCommentary()` — template sentences driven by the score tier,
  short-vs-long-term moving-average agreement, and the RSI/MACD/ADX values;
  no LLM call, this app has no AI dependency). `_technicalHandler` in
  `bin/server.dart` fetches ~500 calendar days of daily candles (enough
  trading days for MA200 even with weekend/holiday gaps) and is public like
  `/api/candles` (no per-user data); only the *list* of symbols to analyze
  (`/api/technical-watchlist*`) is per-user and auth-gated.
- `portfolio_summary.dart` — `computePortfolioSummary()` powers the Portföy
  tab: for each holding, fetches the current price via `fetchChart` (same
  shared cache as everywhere else) and computes P&L *in the holding's own
  currency* (no cross-currency math there). Separately, it fetches Yahoo's
  `TRY=X` symbol (USD/TRY rate — same `fetchChart`, no new external
  dependency) once per request and uses it to convert USD-denominated
  holdings into TRY so the whole portfolio can be summed into one
  `totalValueTry`/`totalPnlTry`. Only `TRY` and `USD` are handled (the only
  two currencies this app's presets/symbols actually return) — anything
  else is shown per-holding but excluded from the TRY totals
  (`valueInTry: null`, counted in `unconvertedCount`). Unlike
  `TechnicalScoreCache`, this is computed fresh on every `/api/portfolio`
  request rather than cached in the background — portfolios are small
  (a handful of holdings), so a live `Future.wait` over them is fast
  enough, and freshness matters more here than for the 400-symbol
  watchlist scan. Each holding also gets an estimated dividend income: a
  second `fetchDividends` call (failures here are swallowed — a missing
  dividend history doesn't break the price/P&L part of the holding) sums
  the last-15-years per-share dividends and multiplies by the held
  quantity. This is a **deliberate simplification** flagged in both the
  backend field docs and `PortfolioScreen`'s summary card: it assumes the
  current quantity was held for the *entire* 15-year window, ignoring when
  the position was actually bought — same "don't overbuild it" spirit as
  `PortfolioStore`'s overwrite-not-merge choice above. Converted to TRY with
  the same `_convertToTry` helper and summed into
  `PortfolioSummary.totalDividendIncomeTry`.
- `backtest.dart` — `runBacktest()` powers the Backtest tab: "if I'd bought
  when the Teknik score crossed a buy threshold and sold when it crossed a
  sell threshold, how would that have performed historically." For each
  simulated day it re-runs `computeTechnicalAnalysis()` over a **fixed**
  trailing window (`_lookbackCandles = 260`, matching the order of magnitude
  of `_technicalHandler`'s own ~500-calendar-day live lookback) ending on
  that day — fixed rather than growing-from-genesis so each simulated day
  costs O(window) instead of O(elapsed days), keeping a multi-year backtest
  well under a second of pure in-process computation with no extra Yahoo
  calls (the one call from `_backtestHandler` below already fetched
  everything needed). Position sizing is deliberately all-or-nothing (100%
  cash ↔ 100% shares, no partial positions, no commission/slippage modeled)
  — same "keep it simple" simplification style as `PortfolioStore`'s
  overwrite-not-merge and the dividend-income estimate above; the result
  also includes a buy-and-hold return over the same window as a benchmark,
  since "did it even beat doing nothing" is the first thing this kind of
  simulation needs to answer. `_backtestHandler` in `bin/server.dart` fetches
  candles starting 400 calendar days *before* the user's chosen start date
  (warm-up for the trailing-window scores, same reasoning as
  `_technicalHandler`'s 500-day fetch) through the chosen end date, then
  hands the whole set to `runBacktest`, which only starts trading once it
  reaches the user's actual start date.
- `yahoo_fundamentals.dart` — fetches company/financial-statement data for
  the Temel Analiz tab. **Requires a cookie+crumb handshake** (`GET
  fc.yahoo.com` for a cookie → `GET query2.finance.yahoo.com/v1/test/
  getcrumb` with that cookie for a crumb, cached ~1h, refreshed once on a
  401) — discovered live during implementation: Yahoo's `quoteSummary` and
  `fundamentals-timeseries` endpoints reject the bare-`User-Agent` requests
  every other `yahoo_*` fetch in this codebase uses (`401 Invalid Crumb`).
  `_ensureCrumb()` dedups concurrent callers via a module-level
  `Future<void>? _inFlightCrumbFetch` — every request that arrives while a
  handshake is already running awaits that same `Future` instead of
  starting its own (see `fundamentals_cache.dart` below for why this
  matters: the frontend fires 4 parallel requests per symbol view, and
  without this a single page open could hit Yahoo's crumb endpoint 4x
  concurrently). `_retryDelays` is deliberately short (two steps, ~11s
  total) — a longer budget was tried and reverted after live testing
  showed retries compounding across this file's multiple sequential Yahoo
  calls (cookie, crumb, data) *and* across `fetchStockOverview`+
  `fetchFinancialHistory` in one `refresh()`, pushing some requests past
  90s; real reliability now comes from the dedup here plus the
  stale-fallback and background pre-sync in `fundamentals_cache.dart`, not
  from a long retry budget.
  `fetchStockOverview()` hits `quoteSummary` (`assetProfile`/`price`/
  `summaryDetail`/`financialData`/`defaultKeyStatistics` modules) for a
  single-period snapshot (sector, country, market cap, PE/PB, dividend
  yield, current FCF/ROA/current-ratio/debt-to-equity).
  `fetchFinancialHistory()` hits the **modern** `fundamentals-timeseries`
  endpoint (NOT `quoteSummary`'s `balanceSheetHistory`/
  `cashflowStatementHistory` modules — those return almost no fields
  anymore, verified live; the real multi-year data lives at
  `/ws/fundamentals-timeseries/v1/finance/timeseries/{symbol}?type=
  annualX,annualY,...`) for ~4 years (not 5 — Yahoo's practical limit) of
  13 named metrics (revenue, net income, FCF, operating cash flow, capex,
  assets, liabilities, equity, current assets/liabilities, retained
  earnings, gross profit, EBIT). **Banks/financial-sector companies don't
  report gross profit/EBIT/current-assets/current-liabilities** (verified
  against `AKBNK.IS` — different balance sheet structure, not a Yahoo gap),
  so those four come back `null` for that sector; every calculator downstream
  is null-safe about it rather than crashing. Both fetchers have their own
  24h cache (fundamentals move quarterly at most).
- `fundamental_analysis.dart` — pure computation (no network calls, same
  "saf Dart, dış kütüphane yok" style as `technical_analysis.dart`):
  `computeFairValueDCF()` (**deliberately simplified** — flat discount rate
  by currency, 10% for USD/30% for TRY given Turkey's structurally high
  nominal-rate environment, rather than a real per-company WACC; growth rate
  from historical FCF trend, clamped to [-15%, 20%]; 5-year projection +
  terminal value — this is *not* investment-grade valuation, and routinely
  disagrees hugely with market price for mature large caps since it ignores
  everything the market prices in beyond 5 years, which is expected
  behavior, not a bug), `computePiotroskiFScore()` (8 of the classic 9
  criteria — "no new shares issued" is dropped since Yahoo doesn't expose a
  historical share-count series here; score is normalized against however
  many criteria are actually computable for that symbol, e.g. `3/6` for a
  bank, not always `x/9`), `computeAltmanZScore()` (classic 5-ratio formula
  — **returns `null` with an explanatory error for banks/financials**, since
  it needs working capital and EBIT, which those companies don't report),
  and `generateProTips()` (same rule-based/no-LLM style as
  `technical_screen.dart`'s `_generateCommentary()`, but sourced from
  fundamentals instead of price action).
- `fundamentals_cache.dart` — `FundamentalsCache` is the DB-backed
  counterpart to `TechnicalScoreCache`'s in-memory one: `ensureFresh()`
  checks the `stock_scores` table's `computed_at` (not `stocks.updated_at`
  — `scores` is the last of the three tables `refresh()` writes, so its
  timestamp is the only one that reflects "the full pipeline actually
  completed"; a partial failure between `stocks` and `stock_scores` would
  make an `updated_at`-based check wrongly call itself fresh forever) and
  only calls Yahoo (via the fetchers above) + recomputes (via the
  calculators above) + upserts all three tables if missing or older than
  24h; otherwise the GET handlers just read straight from Supabase.
  Storing this in Postgres rather than an in-memory map (unlike
  `TechnicalScoreCache`) matters specifically here because Render's free
  tier wipes in-memory state on every cold start — this cache survives
  that. `refresh()` dedups concurrent callers per-symbol via a
  `Map<String, Future<void>>` (`_inFlightRefreshes`, same pattern as
  `yahoo_fundamentals.dart`'s crumb dedup above — needed because the
  frontend's 4 parallel per-symbol requests would otherwise each trigger
  their own full Yahoo fetch+recompute+upsert). Each Yahoo call inside
  `refresh()` is wrapped in a 20s `_yahooFetchTimeout`; if Yahoo still
  fails (429, timeout, or otherwise) and a previously-synced row already
  exists for that symbol, `refresh()` silently falls back to leaving the
  stale row untouched instead of throwing (same "fall back to last known
  result" pattern `coingecko_client.dart` already uses) — the GET handlers
  below surface this as `stale: true` in the JSON rather than an error
  page. Only a symbol's *first-ever* view (no prior row to fall back to)
  still surfaces a hard error. `syncWatchlistedSymbols()` is a background
  job (registered in `main()` below, same trigger pattern as
  `TechnicalScoreCache`'s refresh) that walks every distinct symbol across
  all users' `TechnicalWatchlistStore` rows and calls `ensureFresh()` on
  each — deliberately sequential with a 4s pause *after each symbol that
  actually hit Yahoo* (already-fresh symbols are skipped instantly, no
  wait), unlike `MonthlyLowChecker`'s 4-wide-parallel-batches-every-300ms:
  the goal here isn't throughput, it's keeping load on Yahoo's rate-limit-
  sensitive crumb endpoint low and spread out, so that by the time a user
  actually opens Temel Analiz for a watchlisted symbol it's typically
  already synced and their request never touches Yahoo at all.
  `StockStore`/`FinancialStatementStore`/`StockScoreStore` (bkz.
  `store.dart`) back the three tables and are the only Store classes in this
  codebase that **don't** take a `userId` — `stocks`/`financial_statements`/
  `stock_scores` are public market data, not per-user state, so their RLS
  (bkz. `supabase_schema_fundamentals.sql`) is the inverse of every other
  table: `anon`+`authenticated` get an open `SELECT ... USING (true))`
  policy, no insert/update/delete policy at all (writes only via this
  proxy's `service_role` key, which bypasses RLS regardless).
  `financial_statements.data` is one flat JSONB blob per (symbol, fiscal
  year) matching `FinancialYear.toJson()` — deliberately *not* three separate
  balance-sheet/income-statement/cash-flow JSONB columns, because Yahoo's
  actual data here is a flat set of named metrics, not three structured
  statement objects; inventing that structure would misrepresent what's
  actually stored.

`GET /health` — plain `200 "ok"`, no auth, no dependencies. Exists solely
as a target for Render's health check; `/api/*` routes are the wrong choice
since the watchlist/notifications ones now require auth (see below) and
Render marking the service unhealthy over 401s hangs a deploy for ~15
minutes before failing it.

Key endpoints (all under `/api/`, CORS-open, JSON in/out):
`search`, `candles` (params: `symbol,start,end,interval` where interval is
one of `60m/4h/1d/1wk/1mo/3mo/12mo` — `12mo` and `4h` don't exist in Yahoo
and are synthesized server-side: `12mo` by grouping `1mo` candles in fixed
chunks of 12, `4h` by fetching `60m` candles and grouping by wall-clock
4-hour UTC buckets, *not* positional chunking, since intraday data has
trading-hour/weekend gaps that fixed-size chunks would straddle; an
optional `indicators=rsi,macd` param — only sent when
`MarketApi.candles(includeIndicators: true)` — attaches a full RSI(14)/
MACD(12,26,9) *time series* to each returned candle, computed on
whichever candles are actually being returned (post-synthesis for
`12mo`/`4h`) via `rsiSeries()`/`macdSeriesFor()` in `technical_analysis.dart`
— distinct from `computeTechnicalAnalysis()`, which only needs the latest
value; this is what draws the RSI/MACD sub-panels under the candlestick
chart in `HomeScreen`/`TrackingScreen`, kept pixel-aligned to the candles
above by sharing one `slotWidth` computed once in
`CandlestickChart`'s `LayoutBuilder`, not per-panel),
`watchlist` (GET/add/remove/bulk-add), `favorites` (GET/add/remove, same
shape as `watchlist`), `tracked` (GET returns `{symbol}` or `{symbol:
null}`, POST upserts it — backs the Takip tab), `technical` (GET, params:
`symbol` — public, returns a `TechnicalAnalysisResult`, see
`technical_analysis.dart` above), `technical-watchlist` (GET/add/remove,
same shape as `favorites` — which symbols the Teknik tab shows), `portfolio`
(GET returns a full `PortfolioSummary` — live prices + TRY totals computed
fresh each call, see `portfolio_summary.dart` above; `add`/`remove` take
`{symbol, quantity, costBasis}`/`{symbol}`, `add` is an upsert-overwrite
not a merge), `dividends` (GET, params: `symbol` — public, returns
`{symbol, currency, dividends: [{date, amount}], totalPerShare}`, see
`fetchDividends()` above), `dividend-watchlist` (GET/add/remove, same shape
as `favorites`/`technical-watchlist` — which symbols the Temettü tab
shows), `backtest` (GET, params: `symbol`, `start`/`end` (ISO dates —
trading only happens inside this range, data before it is fetched purely
as lookback/warm-up), `buyThreshold`/`sellThreshold` (default 60/40, must
satisfy `buyThreshold > sellThreshold`), `initialCapital` (default 10000)
— public, returns a `BacktestResult`, see `backtest.dart` above),
`fundamentals/overview`/`fundamentals/fair-value`/`fundamentals/
health-score`/`fundamentals/protips` (GET, params: `symbol` — public, each
reads straight from the `stocks`/`stock_scores` tables after
`FundamentalsCache.ensureFresh()` — see `fundamentals_cache.dart` above;
`fair-value` and `health-score` both include an `error` string field
(`error`/`altmanError`) that's non-null instead of the numeric fields when
that particular calculation isn't available for the symbol, e.g. bank
stocks — the frontend shows that message rather than a bare `null`). All
four are wrapped by `_withFreshFundamentals()` in `bin/server.dart`, which
adds a 25s handler-level timeout around `ensureFresh()` as a defense-in-
depth ceiling on top of `fundamentals_cache.dart`'s own per-call timeouts
— on timeout it falls through to whatever's already in the DB (fresh or
stale) rather than hanging the request. Each response also includes a
`stale` boolean (`FundamentalsCache.isFresh()` against `updated_at` for
`overview`, `computed_at` for the other three) so the frontend can show a
"veriler güncellenemedi, en son bilinen veriler gösteriliyor" banner
instead of silently serving old numbers as if they were current,
`admin/sync-stock/{symbol}` (POST, **not** Supabase-authenticated — guarded
by an `X-Admin-Secret` header checked against the `ADMIN_SYNC_SECRET` env
var; endpoint is fully disabled (503) if that var isn't set, so there's no
default-open admin route; calls `FundamentalsCache.refresh()` directly,
skipping the 24h freshness check),
`notifications` (paginated, 100/page, newest first),
`notifications/check-now` (fire-and-forget — does NOT await the full scan,
since a large watchlist can take minutes; guarded by a module-level
`_checkInProgress` flag against overlapping runs). All
`watchlist*`/`favorites*`/`tracked`/`technical-watchlist*`/`portfolio*`/
`dividend-watchlist*`/`notifications*` endpoints require `Authorization:
Bearer <token>` (see Auth above); `search`/`candles`/`technical`/
`dividends`/`backtest`/`fundamentals*`/`health` don't (`admin/sync-stock`
has its own separate `X-Admin-Secret` gate, not Supabase auth).

`main()` also runs `checker.checkAll()` once at startup and then on a
`Timer.periodic(Duration(hours: 24))` — this only fires while the process
stays alive, there's no OS-level scheduler.

### Frontend (`borsa_takip`)

`main.dart` → `AuthGate` (listens to `Supabase.instance.client.auth
.onAuthStateChange`) shows `LoginScreen` (email/password + Google OAuth via
`supabase_flutter`) when signed out, else `RootShell`. `RootShell` holds an
`IndexedStack` of ten tab screens behind a bottom `NavigationBar`:
`HomeScreen` (chart/table), `NotificationsScreen` (watchlist management +
notification feed — its watchlist-management area itself has two sub-tabs,
"İzleme Listesi" (the existing add/remove/preset UI) and "Puan Sıralaması"
(`widgets/score_ranking_section.dart`'s `ScoreRankingSection`, a
self-contained `StatefulWidget` with its own `MarketApi()`: BIST/ABD/Kripto
category filters that can be combined freely, ascending/descending sort by
the Teknik score, and 50-symbols-per-page pagination — reads
`/api/technical-scores`, which itself reads only from
`TechnicalScoreCache`, see the backend section), while the notification
feed below stays visible regardless of which sub-tab is selected),
`FavoritesScreen` (search + favorite list),
`TrackingScreen` (single-symbol chart — interval chips are
`ChartInterval.tracking`, see the interval section above), and
`TechnicalScreen` (Pivot Points/Moving Averages/Indicators + Buy-Sell
summary for whatever symbols the user has added there — its own
`TechnicalWatchlistStore`-backed list, independent of `HomeScreen`'s
selection or the watchlist/favorites; see `technical_analysis.dart` in the
backend section for the computation; also renders a read-only
`FavoriteSymbolsBar` above the watchlist chips — tapping a favorite calls
the same `_addSymbol` the search field uses, so it's a shortcut into the
existing add-and-select flow rather than a separate code path, and there's
no star toggle *inside* this bar since favorite-ness itself is only ever
changed from `HomeScreen`/`NotificationsScreen`/`FavoritesScreen`, see
below), and `ComparisonScreen` (2-4 symbols overlaid on one line chart, each
normalized to % change from its own first candle — no backend change
needed, it's plain `/api/candles` calls per symbol; `widgets/
comparison_chart.dart`'s doc comment explains the alignment tradeoff: since
symbols can trade on different calendars — BIST closed weekends, crypto
7/24 — series are truncated to the shortest one's length, aligned so
*today* lines up for all of them, rather than attempting real calendar-date
alignment from the pre-formatted `period` strings), `PortfolioScreen`
(add/edit/remove positions by symbol+quantity+cost, live P&L, a
`CustomPainter` donut allocation chart — `widgets/
portfolio_allocation_chart.dart`, no charting package, same approach as
`CandlestickChart` — a single TRY-denominated total, and (per holding, plus
a portfolio-wide total in the summary card) an estimated dividend income
figure with an inline caveat that it assumes the current quantity was held
for the full 15-year window; see `portfolio_summary.dart` in the backend
section for both the USD→TRY conversion and the dividend-income caveat in
full), `DividendScreen` (Temettü tab: own `DividendWatchlistStore`-backed
symbol list, independent of every other tab's selection — same
watchlist-chip pattern as `TechnicalScreen`; selecting a symbol shows its
raw `/api/dividends` history as a date+amount table, no quantity/income math
here, that's `PortfolioScreen`'s job), `BacktestScreen` (Backtest tab:
symbol search + a `showDateRangePicker` range + buy/sell score threshold and
starting-capital inputs, all transient — unlike every other tab there's no
persisted "which symbols" list here, each run is its own one-off experiment;
running it shows the strategy's return next to a buy-and-hold benchmark for
the same window, `widgets/backtest_chart.dart` (a two-series adaptation of
`comparison_chart.dart`'s `CustomPainter` line-chart approach — strategy in
cyan, buy-and-hold in muted slate as the "reference" line) plotting both as
% return over time, and a trade-by-trade table; see `backtest.dart` in the
backend section for the simulation itself and its simplifying assumptions),
and `FundamentalsScreen` (Temel Analiz tab: DCF Fair Value, Piotroski
F-Score, Altman Z-Score, ProTips for whatever symbol is selected — the one
deliberate exception to every other tab's "own independent watchlist"
pattern: it reuses `TechnicalWatchlistStore` directly, so whatever's added
in Teknik shows up here too and vice versa, rather than introducing yet
another near-identical Supabase table; when a calculation isn't available
for a symbol — the common case being Altman Z-Score and two Piotroski
criteria for banks/financial-sector stocks — the card shows the backend's
`error` string instead of a bare blank value; see `fundamental_analysis.dart`
and `fundamentals_cache.dart` in the backend section for the computation,
simplifying assumptions, and DB-backed caching. All four models
(`StockOverview`/`FairValueResult`/`HealthScoreResult`/`ProTipsResult` in
`models/fundamentals.dart`) carry the backend's `stale` boolean; if any of
them is `true` for the currently-selected symbol,
`_FundamentalsResultView` shows a warning banner above the rest of the
page ("Veriler şu an güncellenemedi ... en son bilinen veriler
gösteriliyor") instead of silently presenting old numbers as current — see
the `stale`-fallback behavior in `fundamentals_cache.dart` above for when
this triggers).
Screens mostly own their
own `MarketApi()` instance and don't share state — except favorites:
`RootShell` owns the one `List<String> _favorites` and passes it plus an
`onToggleFavorite` callback down to `HomeScreen`/`NotificationsScreen`/
`FavoritesScreen`, so a star toggled in one tab is immediately reflected in
the others (IndexedStack builds all four tabs eagerly at login, not lazily
per-visit, so without this lift each tab's own fetch-once-in-initState copy
would drift out of sync with the others). `TechnicalScreen` also receives
`_favorites` (for the read-only bar above) but not `onToggleFavorite` — it
can jump to a favorite, not un-favorite it, so it doesn't need the callback.
`HomeScreen` is where the star itself lives day-to-day: a
`_FavoriteToggleButton` next to the "Seçili: SYMBOL" chip in
`ChartResultSection`'s `leadingActions` (filled/outline star matching the
same visual language as the Bildirimler/Favoriler star icons) lets you
favorite whatever you're currently charting without switching tabs first —
previously favoriting only happened from `NotificationsScreen`/
`FavoritesScreen`, so `HomeScreen` receiving `onToggleFavorite` at all is
new. Two cross-tab navigation flows
follow the same pattern: tapping a notification switches to Grafik with
that symbol (`RootShell._openChartFor` → `HomeScreen.requestedSymbol`/
`requestId`), and tapping the track icon next to a favorite switches to
Takip with that symbol (`RootShell._openTrackingFor` →
`TrackingScreen.requestedSymbol`/`requestId`) — in both cases `requestId`
increments on every tap (even re-tapping the same symbol) because
`IndexedStack` keeps the target screen's `State` alive, so a plain prop
change alone wouldn't necessarily be noticed without something for
`didUpdateWidget` to compare against. `TrackingScreen` additionally loads
whatever symbol was last persisted via `/api/tracked` on its own `initState`
(so reopening the app lands back on it without going through Favoriler).
`services/supabase_config.dart` holds the (non-secret) Supabase URL +
anon/publishable key, hardcoded as `String.fromEnvironment` defaults — same
pattern as `API_BASE_URL`.

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
instead of scrolling. `CandlestickChart` is `Stateful`: thin vertical
gridlines are drawn at the same group boundaries as the date-label row
below the chart (`labelEvery`, computed once and shared by both so they
stay aligned), and a `GestureDetector` (`onTapUp`, same code path on web
and mobile — no separate touch/mouse handling needed) maps the tap x
position to a candle index and shows a small `Positioned` overlay `Card`
with that candle's high/low next to it; tapping a different candle just
replaces `_selectedIndex`, which naturally closes the old popup and opens
the new one since it's a single `int?` in `State`, not a stack of dialogs.

Candle "period" labels (e.g. `Q3 25`, `2024-2025`, `31.07.25`, `10.08 14:00`
for the intraday intervals) are formatted server-side per interval — the
frontend just displays `candle.period` as-is, it does no date formatting of
its own for chart data.

`models/interval.dart`'s `ChartInterval` enum covers both long-range
(`daily`/`weekly`/`monthly`/`quarterly`/`yearly`) and intraday
(`hourly`/`fourHour`/`daily`) values in one place since `MarketApi.candles`
needs a single type either way, but no screen shows all seven at once:
`HomeScreen` renders `ChartInterval.longTerm` chips, `TrackingScreen`
renders `ChartInterval.tracking` chips (intraday + weekly/monthly/quarterly,
i.e. everything except the 12-month bucket — Takip's date-range picker was
widened to match Grafik's `firstDate: DateTime(2000)` for this, since the
old 1-year cap left almost nothing to show at monthly/quarterly zoom) —
pick whichever list matches when adding a new interval rather than
iterating `ChartInterval.values`.

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
  `COINGECKO_API_KEY` is also declared there but optional: a free CoinGecko
  "Demo" key (from coingecko.com/en/developers/dashboard) raises the
  crypto300 preset's rate limit well above the shared-IP anonymous tier;
  without it the proxy still works, just retries more and is more likely to
  fall back to the static crypto list under load. `ADMIN_SYNC_SECRET` is
  also declared and also optional, but with the opposite default: leaving
  it unset doesn't degrade a feature, it **disables** `POST /api/admin/
  sync-stock/{symbol}` entirely (503) — see `fundamentals_cache.dart` in
  Architecture above.
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

- BIST200/US-popular-200 preset lists are hand-curated snapshots, not a
  live index feed (Yahoo's actual "most active" screener needs
  cookie/crumb auth this specific preset-list code path doesn't implement
  — `yahoo_fundamentals.dart` *does* implement that handshake now, just for
  a different endpoint, see Architecture above) — expect occasional stale
  or wrong tickers; the checker just skips symbols that fail to fetch.
- The Temel Analiz tab's cookie+crumb handshake (`yahoo_fundamentals.dart`)
  is unofficial/reverse-engineered — Yahoo doesn't document or guarantee
  this endpoint or auth flow, unlike the plain chart/search endpoints the
  rest of this codebase uses, which have been stable for years. If Yahoo
  changes it, `fetchStockOverview`/`fetchFinancialHistory` will start
  throwing `YahooException`s (surfaced as 404s to the frontend) until the
  handshake is updated — this is a meaningfully higher-risk dependency than
  everything else in `yahoo_client.dart`. Separately (and observed live in
  production repeatedly — first traced through with `ISBTR.IS`, then again
  with `BJKAS.IS`): Yahoo rate-limits this handshake more aggressively from
  Render's shared cloud IPs than from a residential dev machine — the exact
  same "Render IP gets 429'd, my laptop doesn't" problem
  `coingecko_client.dart` already has a comment about, confirmed live
  (same-moment request from a dev machine got an instant 200 from
  `getcrumb` while Render's IP exhausted its full retry budget and still
  got 429). That's compounded by a **self-inflicted** second cause found
  during the same investigation: `FundamentalsScreen` fires its 4
  `overview`/`fair-value`/`health-score`/`protips` requests in parallel per
  symbol view, and with no coordination each one independently triggered
  its own crumb handshake — a single page open could hit Yahoo's crumb
  endpoint 4x concurrently, worse than the external rate-limit alone.
  Addressed with a multi-layer fix rather than a single retry tweak (a
  first attempt that just widened the retry budget made things *worse* —
  retries compound across this file's sequential Yahoo calls and across
  both fetchers inside one `refresh()`, and a live test hung 90+ seconds
  before that was caught and reverted): concurrent-request dedup at both
  the crumb-handshake layer (`yahoo_fundamentals.dart`) and the
  per-symbol-refresh layer (`fundamentals_cache.dart`), a short bounded
  retry budget (~11s) plus per-call and per-handler timeouts instead of a
  long one, a stale-data fallback so a failed live refresh serves the last
  known good row (flagged `stale: true`) instead of erroring, and a slow
  background pre-sync job so watchlisted symbols are typically already
  fresh before a user ever opens Temel Analiz for them — see
  `yahoo_fundamentals.dart` and `fundamentals_cache.dart` in the
  Architecture section above for the specifics of each layer. A symbol's
  very first-ever view (nothing to fall back to) can still surface a hard
  error if Yahoo is actively rate-limiting at that moment — this is now
  the only case that isn't fully absorbed by the fix.
- `git` is not installed on the primary dev machine by default; when it is
  installed via winget mid-session, a *new* shell is needed before `git`
  resolves on PATH (the invoking shell keeps its stale PATH).
- The `60m`/`4h` intervals' date-range depth isn't validated anywhere —
  Yahoo itself caps intraday history (roughly the last ~730 days for
  `60m`), and picking an older start date in the Takip tab's date-range
  picker just surfaces whatever error Yahoo returns rather than a friendly
  message.
- Favorites are only synced across tabs within a single running session
  (`RootShell._favorites`, lifted so Grafik/Bildirimler/Favoriler agree with
  each other live) — a second device/tab, or the same app after a full
  reload, only sees the latest state from its own next `/api/favorites`
  fetch, not proactively.

## UI/UX Tasarım Kuralları

Bu proje Flutter/Material kullanıyor, Tailwind CSS yok (ne web'de ne
başka bir yerde) — aşağıdaki kurallar orijinal Tailwind tabanlı bir
tasarım sisteminin niyetini bu projenin gerçek araçlarına (Dart
`TextStyle`/`EdgeInsets`/`ColorScheme`/`BoxDecoration`/widget'lar) çevirir.
Her yeni ekran/bileşen ve mevcut bir ekrana dokunulan her revizyonda
uygulanır; dokunulmayan ekranları geriye dönük güncellemek zorunlu değil
ama o ekrana bir sonraki sefer dokunulduğunda bu kurallara çekilmeli.

**Bu, önceki (açık/pastel slate) tasarım sisteminin yerine geçer** — bu
oturumda eklenmiş olan `lib/theme/app_colors.dart`, `main.dart`'taki
`_buildTheme()` ve `home_screen.dart`'taki kart yapısı henüz *eski* açık
temayı uyguluyor; kod bu yeni koyu/tech temaya göre henüz güncellenmedi
(bir sonraki UI revizyonunda ele alınacak).

### Tema: Modern BIST/Borsa Analitik (Koyu & Tech Tema)

1. **Tema ve arka planlar:**
   - Ana arka plan: koyu/sade — `Color(0xFF020617)` (`slate-950`).
   - Kart/panel arka planı: yarı saydam koyu "glassmorphism" —
     `Color(0xFF0F172A)` (`slate-900`) `withValues(alpha: 0.6)` + arkasında
     `BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12))`
     (`ui.ImageFilter`, `dart:ui` importu gerekir) + `Border.all(color:
     Color(0xFF1E293B).withValues(alpha: 0.8))` (`slate-800/80`) —
     `bg-slate-900/60 backdrop-blur-md border border-slate-800/80` karşılığı.
2. **Canlı gradyanlar ve vurgu renkleri:**
   - Ana vurgu (Yükseliş): neon zümrüt→camgöbeği gradyanı —
     `LinearGradient(colors: [Color(0xFF34D399), Color(0xFF06B6D4)])`
     (`emerald-400` → `cyan-500`), `from-emerald-400 to-cyan-500` karşılığı.
   - İkincil vurgu (Düşüş): gül→mor/eflatun gradyanı —
     `LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFC026D3)])`
     (`rose-500` → `fuchsia-600`), `from-rose-500 to-fuchsia-600` karşılığı.
   - Tech glow efekti: grafik/kart/rozet gibi öne çıkan elemanlarda yumuşak
     renkli gölge — `BoxShadow(color: Color(0xFF10B981).withValues(alpha:
     0.15), blurRadius: 15)` (`shadow-[0_0_15px_rgba(16,185,129,0.15)]`
     karşılığı; renk bullish/bearish'e göre emerald/rose olarak değişir).
3. **Tipografi ve veri gösterimi:**
   - Sayısal veri/fiyatlar: monospace + sıkı tracking —
     `TextStyle(fontFamily: 'RobotoMono', fontWeight: FontWeight.w600,
     letterSpacing: -0.2, color: Color(0xFFF1F5F9))` (`slate-100`) —
     `font-mono`/`font-semibold tracking-tight text-slate-100` karşılığı.
     **Not:** Flutter'da gerçek bir monospace font paket olarak
     eklenmeden (`google_fonts` bağımlılığı ya da `pubspec.yaml`'a asset
     font eklenip `fonts:` altında tanımlanması gerekir) `fontFamily:
     'monospace'` sistemde otomatik bir şeye çözümlenmez — bu proje şu an
     hiç ek font bağımlılığı kullanmıyor, ilk uygulamada bu karar
     (hangi paket/font) verilmeli.
   - Etiketler/ticker'lar: yüksek kontrast soluk metin —
     `TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing:
     0.8, color: Color(0xFF94A3B8))` (`slate-400`) + metni `.toUpperCase()`
     ile büyük harfe çevir (Flutter'da CSS `text-transform` karşılığı yok)
     — `text-xs font-medium text-slate-400 uppercase tracking-wider`
     karşılığı.
4. **Etkileşim ve mikro-animasyonlar:** Buton/kartları `MouseRegion` +
   `AnimatedContainer(duration: Duration(milliseconds: 200))` ile sarıp
   hover'da border rengini `Color(0xFF06B6D4).withValues(alpha: 0.5)`
   (`cyan-500/50`) yap; basılma hissi için `lib/widgets/pressable_scale.dart`
   içindeki `PressableScale`'i kullan (zaten `Listener` tabanlı olduğundan
   içindeki Material buton/kartın kendi tıklama davranışını bozmuyor) —
   `hover:border-cyan-500/50 transition-all duration-200
   active:scale-[0.98]` karşılığı. Önceki tasarımdaki 150ms yerine bu
   temada geçiş süresi 200ms.

### Görsel doğrulama: Playwright MCP

Bu kuralları uygulayan bir değişiklikten sonra sonucu görsel olarak
doğrulamak için proje kapsamında bir Playwright MCP sunucusu tanımlı
(`.mcp.json`, `claude mcp add playwright --scope project -- npx -y
@modelcontextprotocol/server-playwright` ile eklendi). MCP sunucu
tanımları yalnızca **oturum başlangıcında** yüklenir — `.mcp.json`'a yeni
bir sunucu eklendiğinde o an açık olan oturumda görünmez, kullanılabilmesi
için Claude Code'un yeniden başlatılması gerekir. Canlı siteyi (`https://
ercinnn.github.io/borsa/`) login gerektirmeden incelemek login ekranıyla
sınırlı kalır; login sonrası ekranları görsel doğrulamak için ya gerçek
bir Supabase hesabıyla giriş yapılmalı ya da `claude-in-chrome` ile
kullanıcının zaten oturum açmış olduğu gerçek Chrome sekmesi kullanılmalı
(bkz. Deployment bölümündeki proxy_server yerel çalıştırma notu — yerelde
çalıştırmak için `proxy_server/.env` de gerekiyor).
