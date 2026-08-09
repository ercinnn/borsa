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
- `borsa_takip/` — the Flutter web frontend. It only ever talks to
  `proxy_server` (`http://localhost:8787`, hardcoded in
  `lib/services/market_api.dart`), never to Yahoo/CoinGecko directly.

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
flutter run -d chrome --web-port=5000
dart analyze lib
flutter test                      # runs test/widget_test.dart
```

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

## Architecture

### Backend (`proxy_server`)

Single-file router (`bin/server.dart`) wired to four `lib/` modules:

- `yahoo_client.dart` — `fetchChart()` is the one shared function that hits
  Yahoo's `/v8/finance/chart/{symbol}` endpoint and parses OHLC candles.
  Both `/api/candles` and the monthly-low checker call it — don't duplicate
  Yahoo-parsing logic elsewhere.
- `store.dart` — `WatchlistStore` and `NotificationStore`, both flat JSON
  files under `proxy_server/data/` (gitignored, created on first run,
  seeded with 8 default symbols). No database.
- `monthly_low_checker.dart` — `MonthlyLowChecker.checkAll()` walks the
  watchlist sequentially (300ms delay between symbols to avoid Yahoo
  rate-limiting) and, per symbol, fetches the current month's daily candles
  and compares today's low against the lowest of all *prior* days this
  month. If today set a new low, it appends a notification (deduped by
  `symbol+date`).
- `preset_lists.dart` / `coingecko_client.dart` — static curated symbol
  lists (`bist100Symbols`, `usPopular100Symbols`) and a live CoinGecko
  top-N-by-market-cap fetch, used by `/api/watchlist/bulk-add`.

Key endpoints (all under `/api/`, CORS-open, JSON in/out):
`search`, `candles` (params: `symbol,start,end,interval` where interval is
one of `1d/1wk/1mo/3mo/12mo` — `12mo` doesn't exist in Yahoo and is
synthesized server-side by grouping `1mo` candles in chunks of 12),
`watchlist` (GET/add/remove/bulk-add), `notifications` (paginated, 100/page,
newest first), `notifications/check-now` (fire-and-forget — does NOT await
the full scan, since a large watchlist can take minutes; guarded by a
module-level `_checkInProgress` flag against overlapping runs).

`main()` also runs `checker.checkAll()` once at startup and then on a
`Timer.periodic(Duration(hours: 24))` — this only fires while the process
stays alive, there's no OS-level scheduler.

### Frontend (`borsa_takip`)

`main.dart` → `RootShell` holds an `IndexedStack` of two independent tab
screens behind a bottom `NavigationBar`: `HomeScreen` (chart/table) and
`NotificationsScreen` (watchlist management + notification feed). They
don't share state beyond both owning their own `MarketApi()` instance.

`services/market_api.dart` is the only HTTP boundary — every screen goes
through it, never calls `http` directly. All failures surface as
`ApiException` with a Turkish message (including a specific one for "proxy
not running").

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

## Known rough edges

- BIST100/US-popular-100 preset lists are hand-curated snapshots, not a
  live index feed (Yahoo's actual "most active" screener needs
  cookie/crumb auth this proxy doesn't implement) — expect occasional stale
  or wrong tickers; the checker just skips symbols that fail to fetch.
- `git` is not installed on the primary dev machine by default; when it is
  installed via winget mid-session, a *new* shell is needed before `git`
  resolves on PATH (the invoking shell keeps its stale PATH).
