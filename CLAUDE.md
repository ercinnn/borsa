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
  Yahoo-parsing logic elsewhere.
- `store.dart` — `WatchlistStore`, `NotificationStore`, `FavoritesStore`,
  `TrackedSymbolStore`, all persisted in a Supabase Postgres project via
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
  currently showing.
  Table schema: `proxy_server/supabase_schema.sql` +
  `supabase_schema_auth.sql` + `supabase_schema_favorites.sql` (run once
  each, in order, in the Supabase SQL Editor — the second adds `user_id`
  and RLS to the base tables, the third adds the `favorites` and
  `tracked_symbol` tables). Requires `SUPABASE_URL` and
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
  lists (`bist100Symbols`, `usPopular100Symbols`, `cryptoFallbackSymbols`)
  and a live CoinGecko top-N-by-market-cap fetch, used by
  `/api/watchlist/bulk-add`. `fetchTopCryptoSymbols()` retries a few times
  with backoff on CoinGecko 429s, optionally authenticated via
  `COINGECKO_API_KEY` (`x-cg-demo-api-key` header, opt-in — see Deployment);
  if all retries fail and there's no cached result, the `crypto200` handler
  falls back to the static `cryptoFallbackSymbols` list rather than erroring.

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
trading-hour/weekend gaps that fixed-size chunks would straddle),
`watchlist` (GET/add/remove/bulk-add), `favorites` (GET/add/remove, same
shape as `watchlist`), `tracked` (GET returns `{symbol}` or `{symbol:
null}`, POST upserts it — backs the Takip tab), `notifications` (paginated,
100/page, newest first), `notifications/check-now` (fire-and-forget — does
NOT await the full scan, since a large watchlist can take minutes; guarded
by a module-level `_checkInProgress` flag against overlapping runs). All
`watchlist*`/`favorites*`/`tracked`/`notifications*` endpoints require
`Authorization: Bearer <token>` (see Auth above); `search`/`candles`/
`health` don't.

`main()` also runs `checker.checkAll()` once at startup and then on a
`Timer.periodic(Duration(hours: 24))` — this only fires while the process
stays alive, there's no OS-level scheduler.

### Frontend (`borsa_takip`)

`main.dart` → `AuthGate` (listens to `Supabase.instance.client.auth
.onAuthStateChange`) shows `LoginScreen` (email/password + Google OAuth via
`supabase_flutter`) when signed out, else `RootShell`. `RootShell` holds an
`IndexedStack` of four tab screens behind a bottom `NavigationBar`:
`HomeScreen` (chart/table), `NotificationsScreen` (watchlist management +
notification feed), `FavoritesScreen` (search + favorite list), and
`TrackingScreen` (single-symbol intraday chart). Screens mostly own their
own `MarketApi()` instance and don't share state — except favorites:
`RootShell` owns the one `List<String> _favorites` and passes it plus an
`onToggleFavorite` callback down to `HomeScreen`/`NotificationsScreen`/
`FavoritesScreen`, so a star toggled in one tab is immediately reflected in
the others (IndexedStack builds all four tabs eagerly at login, not lazily
per-visit, so without this lift each tab's own fetch-once-in-initState copy
would drift out of sync with the others). Two cross-tab navigation flows
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
renders `ChartInterval.intraday` chips — pick whichever list matches when
adding a new interval rather than iterating `ChartInterval.values`.

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
  crypto200 preset's rate limit well above the shared-IP anonymous tier;
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

- BIST100/US-popular-100 preset lists are hand-curated snapshots, not a
  live index feed (Yahoo's actual "most active" screener needs
  cookie/crumb auth this proxy doesn't implement) — expect occasional stale
  or wrong tickers; the checker just skips symbols that fail to fetch.
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
`TextStyle`/`EdgeInsets`/`ColorScheme`/widget'lar) çevirir. Her yeni
ekran/bileşen ve mevcut bir ekrana dokunulan her revizyonda uygulanır;
dokunulmayan ekranları geriye dönük güncellemek zorunlu değil ama o
ekrana bir sonraki sefer dokunulduğunda bu kurallara çekilmeli.

1. **Boşluklar (Spacing):** Sıkışık tasarımlara izin verme. Kart/konteyner
   iç boşluğu minimum `EdgeInsets.all(24)` (Tailwind `p-6` karşılığı).
   Elemanlar arası boşluk için `SizedBox(height: 16)`/`SizedBox(height: 24)`
   ya da `Wrap(spacing: 16, runSpacing: 16)` (`gap-4`/`gap-6` karşılığı).
2. **Renk sistemi:** Tailwind `slate` paletinin karşılıkları:
   - Arka planlar: `Color(0xFFF8FAFC)` (`slate-50`) ya da
     `Color(0xFFF1F5F9)` düşük opaklıkla (`slate-100/50`).
   - Kartlar: beyaz zemin + `Border.all(color: Color(0xFFE2E8F0).withValues(alpha: 0.8))`
     + `BorderRadius.circular(12)` + hafif gölge (`Card(elevation: 1)` ya da
     `BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,2))`) —
     `bg-white border border-slate-200/80 shadow-sm rounded-xl` karşılığı.
   - Metinler: ana başlıklar `Color(0xFF0F172A)` (`slate-900`), ikincil
     metinler `Color(0xFF64748B)` (`slate-500`).
   Bu renkleri her yerde tekrar yazmak yerine tek bir yerde (ör.
   `lib/theme/app_colors.dart`) sabit olarak tanımlayıp oradan kullan.
3. **Tipografi:** Başlıklarda `TextStyle(fontWeight: FontWeight.w600,
   letterSpacing: -0.2)` (`font-semibold tracking-tight`); etiketlerde
   `TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.8,
   color: Color(0xFF94A3B8))` + metni `.toUpperCase()` ile büyük harfe
   çevir (Flutter'da CSS `text-transform` karşılığı yok, string'i kendin
   büyük harfe çevirmen gerekiyor) — `text-xs uppercase tracking-wider
   text-slate-400 font-medium` karşılığı.
4. **Etkileşimler:** Tıklanabilir her elemanı (buton, kart, link) `InkWell`/
   `GestureDetector` ile sar; basılma anında hafif küçülme için
   `AnimatedScale(scale: pressed ? 0.98 : 1.0, duration:
   Duration(milliseconds: 150))`, hover'da gölge artışı için `MouseRegion`
   + `AnimatedContainer(duration: Duration(milliseconds: 150))` kullan
   (`transition-all duration-150 active:scale-[0.98] hover:shadow-md`
   karşılığı). Web'de `InkWell`'in kendi hover/splash efekti zaten temel
   bir geri bildirim verir, üstüne tam bu kuralı eklemek gerekmiyorsa en
   azından `InkWell` kullanmayı atlama.
5. **Layout ve hizalama:** Mevcut `Row`/`Column`/`Wrap`/`LayoutBuilder`
   yapısını bozma (bkz. `candlestick_chart.dart`'taki responsive
   `LayoutBuilder` kullanımı) — masaüstü ve mobil web'de aynı ekranın
   düzgün göründüğünden emin ol, sabit genişlik/yükseklik yerine
   `Expanded`/`Flexible`/`Wrap` tercih et.
