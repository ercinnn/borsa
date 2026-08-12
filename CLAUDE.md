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
  Yahoo's `/v8/finance/chart/{symbol}` endpoint and parses OHLC**V** candles
  (`RawCandle.volume` — added alongside the candlestick chart's volume-bar
  panel; nullable since Yahoo sometimes omits it, esp. in `12mo`/`4h`
  synthesized groups, see `_sumVolume()` in `bin/server.dart` below).
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
  `TabPreferencesStore`, all persisted in a Supabase Postgres project via
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
  currently showing. `TabPreferencesStore` is the same one-row-per-user
  upsert shape again, but for the Ayarlar tab: a `hidden_tabs` jsonb array
  of tab keys the user has switched off in the bottom nav (empty/no row =
  everything visible). It doesn't validate the keys it's given against a
  known tab list — same "don't overbuild it" simplicity as every other
  store here — that's the frontend's job (`models/root_tabs.dart`, see the
  frontend section). `TechnicalWatchlistStore` is the same shape as
  `FavoritesStore` again (own `technical_watchlist` table, no seeding, no
  notification side-effects) — it's just which symbols the Teknik tab
  currently analyzes; unrelated to `WatchlistStore`/`FavoritesStore`.
  `PortfolioStore` backs
  the Portföy tab: one row per `(user_id, symbol)`
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
  `supabase_schema_dividends.sql` +
  `supabase_schema_tab_preferences.sql` (run once each, in order,
  in the Supabase SQL Editor — the second adds
  `user_id` and RLS to the base tables, the third adds the `favorites` and
  `tracked_symbol` tables, the fourth adds `technical_watchlist`, the fifth
  adds `portfolio_holdings`, the sixth adds `dividend_watchlist`, and the
  seventh adds `tab_preferences`, the `TabPreferencesStore` table above).
  `supabase_schema_fundamentals.sql`/`supabase_schema_fundamentals_watchlist
  .sql` still exist on disk but are **obsolete** — they backed the removed
  Temel Analiz tab (see "Removed: Temel Analiz tab" below) and a fresh
  setup no longer needs to run them; the `stocks`/`financial_statements`/
  `stock_scores`/`fundamentals_watchlist` tables they created can be
  dropped manually in Supabase if reclaiming the space matters, nothing in
  the app reads them anymore. Requires `SUPABASE_URL` and
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
  rather than erroring. CoinGecko's `/coins/markets` `per_page` silently
  caps at 250 — requesting more doesn't error, it just falls back to
  CoinGecko's own default of 100 (discovered live: `crypto300` was
  returning only 100 symbols, all already in the watchlist, so "Kripto İlk
  300 Ekle" reported 0 added). `fetchTopCryptoSymbols()` paginates in fixed
  250-item pages when `count` exceeds that ceiling, always requesting the
  *same* `per_page` across pages and slicing the last page down to what's
  still needed — CoinGecko's `page` offset is relative to that request's
  own `per_page`, so mixing page sizes across requests (e.g. page 2 with
  `per_page=50` after a page 1 of `per_page=250`) would silently fetch the
  wrong rank range (51-100 instead of 251-300) rather than erroring.
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
`CandlestickChart`'s `LayoutBuilder`, not per-panel; every candle also
carries `volume` unconditionally — no separate opt-in param, unlike
`rsi`/`macd` — summed across `12mo`/`4h` grouping by `_sumVolume()`, `null`
if every raw candle in that group was missing it),
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
`tab-preferences` (GET returns `{hiddenTabs: [...]}`, POST takes
`{hiddenTabs: [...]}` and upserts it wholesale — no add/remove pair like
the watchlist-shaped endpoints, since the frontend always has the full set
in hand already; backs the Ayarlar tab, see `TabPreferencesStore` above),
`notifications` (paginated, 100/page, newest first),
`notifications/check-now` (fire-and-forget — does NOT await the full scan,
since a large watchlist can take minutes; guarded by a module-level
`_checkInProgress` flag against overlapping runs). All
`watchlist*`/`favorites*`/`tracked`/`technical-watchlist*`/`portfolio*`/
`dividend-watchlist*`/`tab-preferences`/
`notifications*` endpoints require `Authorization:
Bearer <token>` (see Auth above); `search`/`candles`/`technical`/
`dividends`/`backtest`/`health` don't.

`main()` also runs `checker.checkAll()` once at startup and then on a
`Timer.periodic(Duration(hours: 24))` — this only fires while the process
stays alive, there's no OS-level scheduler.

### Frontend (`borsa_takip`)

`main.dart` → `AuthGate` (listens to `Supabase.instance.client.auth
.onAuthStateChange`) shows `LoginScreen` (email/password + Google OAuth via
`supabase_flutter`) when signed out, else `RootShell`. `RootShell` holds an
`IndexedStack` of ten tab screens behind a bottom `ScrollableBottomNav`
(`widgets/scrollable_bottom_nav.dart` — a custom nav bar, not the built-in
Material `NavigationBar`: with this many possible tabs the built-in widget
squeezed every label to fit the screen width and wrapped/overlapped text,
so this one gives each item a fixed width and only switches to a
horizontally-scrolling `SingleChildScrollView` once the visible items no
longer fit that width, otherwise stretching evenly like the old widget
did):
`HomeScreen` (chart/table), `NotificationsScreen` (watchlist management +
notification feed — its watchlist-management area itself has two sub-tabs,
"İzleme Listesi" (the existing add/remove/preset UI — the BIST/ABD/Kripto
category `TabBar` + symbol-chip `Wrap` below it can be collapsed with a
"Gizle"/"Göster" toggle next to the "`X` sembol izleniyor" count, added
once preset sizes grew large enough (BIST 200 + ABD 200 + Kripto 300, and
the crypto preset is additive across repeated clicks — see
`coingecko_client.dart` above — so a watchlist can grow past 700+ symbols)
that the un-collapsed chip list became unwieldy; the count and the
notification feed below stay visible either way, only the tab+chip section
folds) and "Puan Sıralaması"
(`widgets/score_ranking_section.dart`'s `ScoreRankingSection`, a
self-contained `StatefulWidget` with its own `MarketApi()`: BIST/ABD/Kripto
category filters that can be combined freely, ascending/descending sort by
the Teknik score, and 50-symbols-per-page pagination — reads
`/api/technical-scores`, which itself reads only from
`TechnicalScoreCache`, see the backend section), while the notification
feed below stays visible regardless of which sub-tab is selected — both
sub-tabs are driven by their own `TabController`, so
`_NotificationsScreenState` needs `TickerProviderStateMixin` (plural) not
`SingleTickerProviderStateMixin`; using the singular mixin with two
controllers compiles fine but throws at runtime the moment the screen is
opened ("`SingleTickerProviderStateMixin` can only be used as a
`TickerProvider` once") — hit live and fixed in this codebase, worth
remembering before adding a third `TabController` anywhere in this file),
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
and `SettingsScreen` (Ayarlar tab: lets the user hide any
of the other nine tabs from the bottom nav via a `SwitchListTile` per tab —
`models/root_tabs.dart`'s `toggleableRootTabs` is the single ordered list
of tab metadata (key/label/title/icon) shared by this screen, `RootShell`'s
`IndexedStack` ordering, and its `ScrollableBottomNav` items, so a tab's
identity is never duplicated three times. Ayarlar itself is not in that
list and can't be hidden — `RootShell` appends it separately
(`settingsRootTab`) so there's always a way back in. Persisted per-user in
Supabase (`tab_preferences` table via the backend's `TabPreferencesStore`,
see Architecture above) rather than locally, so the choice follows the
user across devices. If the tab currently on screen gets hidden,
`RootShell._leaveIfHidden()` switches to the first still-visible tab
automatically; conversely, tapping a notification or a favorite's track
icon into a *hidden* Grafik/Takip tab (`_openChartFor`/`_openTrackingFor`)
silently un-hides it rather than showing content with no corresponding nav
button — documented inline in `SettingsScreen`'s helper text).
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

`main.dart`'s `MaterialApp` sets `locale: const Locale('tr')` +
`flutter_localizations`'s three `Global*Localizations.delegate`s. Without
this, Flutter's own Material dialogs (`showDateRangePicker`, used by
`HomeScreen`/`TrackingScreen`/`BacktestScreen`/`ComparisonScreen`) fell
back to `en_US` and rendered their calendar in month/day order — every
`DateFormat` the app itself uses for display text was already
`dd.MM.yyyy`/`dd.MM.yyyy HH:mm`, only the picker's own built-in UI was
wrong, so this was a one-line root-cause fix rather than a per-screen one.
Pulling in `flutter_localizations` (an SDK package, not pub.dev) forced
`intl` from `^0.19.0` to `^0.20.2` in `pubspec.yaml` (SDK version pinning —
`flutter_localizations` depends on a specific `intl` version and both
packages have to agree).

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
stay aligned). SMA(20)/EMA(50) are computed client-side (`_simpleMovingAverage`/
`_exponentialMovingAverage`, pure functions over `candle.close` — unlike
RSI/MACD there's no backend round-trip for these, the math is trivial
enough not to warrant one) and drawn as two overlay lines directly on the
price canvas (amber/cyan, `AppColors.amber500` added specifically so they
don't collide with the emerald/rose candle colors or the cyan/fuchsia MACD
lines). A crosshair replaces the old tap-only popup: `MouseRegion.onHover`
(web) and `GestureDetector.onPanDown`/`onPanUpdate` (touch) both feed one
`_hoverIndex` state, which "snaps" to the nearest candle on both axes
(vertical line at the candle's x-center, horizontal line at its close
price — not the raw pointer position, so no need to track pointer Y
separately). `_RsiPainter`/`_MacdPainter`/`_VolumePainter` each also accept
`highlightIndex` and draw a matching vertical line segment via the shared
`_paintCrosshairLine()` helper, so the crosshair visually spans every panel
even though each panel is its own `CustomPaint`/`CustomPainter`. A
`_OhlcRibbon` above the chart shows the hovered candle's (or, with nothing
hovered, the *last* candle's) period/open/high/low/close/volume live —
close is marked with ▲/▼ in addition to color, so the direction doesn't
rely on hue alone (red-green color-blindness; same reasoning applied to
`score_ranking_section.dart`'s `_ScoredSymbolTile`, which used to show only
a colored `X/100` score with no textual Al/Sat tier — now also prints
`SummarySignal.forScore(score).label` beneath it, thresholds copied from
`summarySignalForScore()` in the backend's `technical_analysis.dart`).

`utils/candle_padding.dart`'s `fetchCandlesWithMinimum()` addresses a real
usability bug: a narrow date range + coarse interval (e.g. a 2-month range
with "Aylık"/`1mo`) returns so few candles that `CandlestickChart`'s
`slotWidth` clamp (`.clamp(1.5, CandlestickChart.maxSlotWidth)`) can't
stretch them to fill the card — the chart renders as a thin sliver in a
mostly-empty card. `HomeScreen`/`TrackingScreen` (the only two screens with
a date-range picker + `CandlestickChart`) call it instead of
`MarketApi.candles()` directly: it fetches the user's chosen range first
(no extra cost in the common case), and only if the result has fewer
candles than `_estimateMinCandles(context)` — `(MediaQuery width minus a
per-screen "chrome" constant) / CandlestickChart.maxSlotWidth`, clamped to
`[8, 60]` so a huge desktop window doesn't demand decades of `12mo` history
— does it re-fetch with an earlier, heuristically-computed start date (a
rough calendar-days-per-candle table per `ChartInterval`, ×1.4 overshoot,
clamped to `DateTime(2000)` and, for intraday, to Yahoo's ~730-day ceiling)
wrapped in try/catch so a second request that oversteps Yahoo's history
limit falls back to the original (working) result instead of surfacing an
error. The user's own `_dateRange` selection is never mutated — only the
fetch is widened; re-opening the picker still shows what they actually
picked. `paddingCandleCount` (how many of the *returned* candles came from
this padding, computed as the simple difference between the padded and
original candle counts — both calls return chronologically, so no date
parsing of the server-formatted `period` strings is needed) flows through
`ChartResultSection` into `CandlestickChart`, which renders that many
leading candles at reduced opacity behind a shared `_paintPaddingBand()`
band + divider line (called by all four panel painters, same pattern as
`_paintCrosshairLine()`) and a "← Otomatik eklendi" label on the price
panel. The screens also show a one-time `SnackBar` after such a fetch —
one message when padding succeeded (names the effective start date), a
different one when extending didn't actually help (`historyLimited`, e.g.
a recently-listed symbol has no more history to give) — matching the one
existing `ScaffoldMessenger.showSnackBar` precedent in
`tracking_screen.dart`.

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
  fall back to the static crypto list under load.
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
  cookie/crumb auth this preset-list code path doesn't implement) —
  expect occasional stale or wrong tickers; the checker just skips symbols
  that fail to fetch.
- **Removed: Temel Analiz tab** (DCF Fair Value/Piotroski/Altman/ProTips,
  backed by `yahoo_fundamentals.dart`/`fundamental_analysis.dart`/
  `fundamentals_cache.dart` and the `stocks`/`financial_statements`/
  `stock_scores`/`fundamentals_watchlist` Supabase tables). Removed rather
  than kept-and-fixed after live testing kept surfacing "Sembol bulunamadı"
  even for valid symbols — traced to Yahoo's undocumented `quoteSummary`
  cookie+crumb handshake being rate-limited/blocked from Render's shared
  cloud IP (the multi-layer mitigation described in earlier versions of
  this file — crumb dedup, stale-fallback, background pre-sync — reduced
  but never eliminated it, since the underlying cause is Yahoo throttling
  the IP, not a bug in this codebase). Before removing, free/paid
  alternative fundamentals APIs were checked for BIST (Borsa Istanbul)
  coverage specifically, since that's the market this app cares most about
  and most providers skip it entirely: Twelve Data has XIST fundamentals
  but only on a paid plan; Financial Modeling Prep's free (and most paid)
  tiers cover US-listed companies only. No free, reliable, officially
  documented source covering both BIST and US fundamentals was found, so
  rather than trade one flaky unofficial integration for another (or add a
  paid dependency to a personal app), the tab was dropped. The two
  `supabase_schema_fundamentals*.sql` files are kept on disk for history
  but are no longer run for a fresh setup (see the `store.dart` bullet
  above); their tables can be dropped manually in Supabase if desired.
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
