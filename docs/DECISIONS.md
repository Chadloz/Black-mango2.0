# Black Mango 2.0 decisions

Why things are the way they are. Newest first within each section. No portal URLs, MAC addresses, or logins in this file: the repo is public.

## How we work

- Research first (docs, GitHub issues, existing open source) before building anything custom. Skip only for custom UI and app-specific logic.
- Before each build, settle the small decisions up front with multiple-choice questions, each with a recommended pick and a "write your own" option.
- Chad runs every command; Claude writes the code. Changes ship as installer scripts that refuse to overwrite files that changed locally.
- Every reply with something to run has it in the reply: the file attached every time, and small scripts also as a paste-in Terminal block.
- Run downloaded installers by newest match, so a "(1)" copy or a re-download never trips it up, and never delete before downloading:
  python3 "$(ls -t ~/Downloads/NAME*.py | head -1)"
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
- Movies and shows (step 2): a searchable category menu next to the account filter, opening on the last category you used (remembered per account). The portal's own "All" category is hidden (it would mean the full crawl). A big category shows its first titles right away and keeps loading the rest in the background. Titles sort A to Z like the rest of the app, so the A-Z bar keeps working. Under "All accounts", Stalker titles appear once their category has been opened or searched. Cached categories refresh after 24 hours on next open, plus a manual refresh. Portal search runs on Enter; local results still filter as you type. Plot, cast, year, and rating are saved with each title so details open instantly. Opening a show loads its first season right away and the others in the background. Movie and episode failover includes Stalker in both directions, same as live.

What the movies probe found (October 2026, one German/EU portal)
- Movies and shows are separate types (vod, series), 14 titles per page, with the portal's own "All" category first.
- Each title carries plot, cast, director, genres, year, IMDb rating, and a TMDB poster link, so nothing extra is fetched to open a page.
- Movie links come from create_link (type vod) and, unlike live links, can be reused and seeked (Range works), so resume and the player's own reconnects just work.
- A show's seasons come back in one request (movie_id with season_id 0); each season lists its episode numbers. An episode plays as its season's command plus the episode number. So "first season right away, the rest in the background" isn't needed: all seasons arrive at once.
- The account card shows the portal's totals (its "All" counts); titles are cached as you open categories or search.
- Portal search covers movies and shows.
- Channel switching on its own is fast (about 1 s, even with the old channel still open). The long waits seen in the app came from requests piling up, which the one-connection fix stops; the wait message now just says the provider is starting the channel.

One connection per account
- What we saw: a Stalker MAC gets one stream at a time. While it's busy, the stream server parks new requests and answers ~40-48 s later, often with 509 ("too many connections"). Requests the app had walked away from sat in that queue, and the player's own quick retries joined it.
- So: one request per Stalker account at a time (a new channel, or the player's own retry, closes the older request instead of queueing behind it), and anything you walked away from is cancelled when you pick something else.
- The player waits up to a minute for a Stalker server instead of retrying every 15 s. After about 6 s it says it's waiting for the provider to free up the connection. If nothing comes, it falls back to the same channel on your other accounts.
- Flipping through a Stalker account's channels: the portal is asked only once you stay on one for about a second.
- Stalker live requests don't send a Range header (live streams can't seek; the plain request is what works).
- A 509 counts as "busy", not "server down".
- Smart paste: with several URLs, the one labeled Portal or Panel wins, else the first ending in /c/ or portal.php. With several MACs, offer one account each after a confirm.
- Credit for stalkerhek: README plus file headers.
