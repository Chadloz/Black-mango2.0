# Black Mango 2.0 decisions

Why things are the way they are. Newest first within each section. No portal URLs, MAC addresses, or logins in this file: the repo is public.

## How we work

- Research first (docs, GitHub issues, existing open source) before building anything custom. Skip only for custom UI and app-specific logic.
- Before each build, settle the small decisions up front with multiple-choice questions, each with a recommended pick and a "write your own" option.
- Chad runs every command; Claude writes the code. Changes ship as installer scripts that refuse to overwrite files that changed locally.
- Development chats live in the Black Mango Project so later sessions can search them. This file is the short version.

## Brand (October 2026)

- Logo: the black mango with the cut orange slice. Source art came with a fake transparency checkerboard baked in; the app uses a cleaned transparent cutout (assets/brand/logo.png).
- Top bar: logo centered above a smaller "Black Mango" wordmark (bar 72 px, logo 40 px, wordmark 16 px).
- Home welcome screen: big logo above "Welcome to Black Mango". Settings > About: small logo beside the version line.
- App icon (Dock, Finder, desktop, and later the release download): the logo on a mango-orange squircle. macOS Tahoe boxes non-squircle icons in gray, so the icon is a full squircle on Apple's template grid. Windows uses the same tile.

## Stalker portals (October 2026)

Plan
- Live channels load fully in the background after adding an account (all at once if the portal allows, otherwise page by page, 4 pages at a time; about 45 seconds for ~2,600 channels at 14 per page). Channels appear all at once when done, with progress in the account's status line, like Xtream.
- Movies and shows are NOT crawled up front (a full crawl of ~52,000 titles is ~3,700 requests and about 15 minutes from one MAC: looks like scraping, and it doesn't help). They load by the portal's own categories when opened, cached in the database.
- Search goes to the portal (it searches all titles in one request).
- Every play and every reconnect asks the portal for a fresh link (create_link). Links carry tokens that expire within minutes. The relay asks for a fresh link on its own reconnects too.
- Our own implementation. crispy-stalker's license is incompatible with GPL. stalkerhek (both the original and the kidpoleon fork) is GPL-3.0, so it can be studied and adapted with credit.

Settled details
- Device identity: serial and device ID are made from the MAC automatically (serial = first 13 of MD5, device ID = SHA-256, signature = SHA-256 of serial + MAC). Both can be overridden under Advanced in Add Account, like 1.x's optional fields.
- Portal address: whatever the user pastes (/c/, /stalker_portal/c/, portal.php, load.php), the app tries the likely API addresses (portal.php first, then load.php variants) and remembers the one that answered.
- Timezone sent to the portal: the Mac's own timezone.
- Now/next guide for Stalker channels: included from the start, with the same request limits and 429/404 backoff as Xtream.
- Live failover works across account types in both directions (Stalker, Xtream, M3U), matched by channel name.
- Keep-alive: a watchdog check-in every 2 minutes while a Stalker channel plays. If the session expired while browsing, the app logs in again quietly on the next request.
- A MAC that's busy on another device gets the same "account already in use" message as Xtream.
- Movies and shows (next step): a searchable category menu next to the account filter. Under "All accounts", Stalker titles appear once their category has been opened or searched. Cached categories refresh after 24 hours on next open, plus a manual refresh. Portal search runs on Enter; local results still filter as you type. Plot, cast, year, and rating are saved with each title so details open instantly.
- Smart paste: with several URLs, the one labeled Portal or Panel wins, else the first ending in /c/ or portal.php. With several MACs, offer one account each after a confirm.
- Credit for stalkerhek: README plus file headers.
