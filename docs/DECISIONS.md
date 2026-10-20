# Black Mango 2.0 decisions

Why things are the way they are. Newest first within each section. No portal URLs, MAC addresses, or logins in this file: the repo is public.

## How we work

- Research first (docs, GitHub issues, existing open source) before building anything custom. Skip only for custom UI and app-specific logic.
- Before each build, settle the small decisions up front with multiple-choice questions, each with a recommended pick and a "write your own" option.
- Chad runs every command; Claude writes the code. Changes ship as installer scripts that refuse to overwrite files that changed locally.
- Scripts ship as downloads (pasting long scripts into Terminal is fragile). The file comes first, then numbered steps right under it: download, the one-line command to run it and what it should print, restart, what to test and send back.
- Each installer carries everything it depends on, so the order you run them in never matters.
- Run downloaded installers by newest match, so a "(1)" copy or a re-download never trips it up, and never delete before downloading:
  python3 "$(ls -t ~/Downloads/NAME*.py | head -1)"
- Development chats live in the Black Mango Project so later sessions can search them. This file is the short version.

## Smoother live TV (October 2026)

- Extra buffer for flaky channels: a live channel that stalls twice within 5 minutes gets 3 more seconds of cushion, up to 15 seconds in all (your "Buffer before a channel starts" setting plus its extra). It's remembered per channel on each account, even after restarting, and takes effect at the next rebuffer. After 30 minutes of smooth watching it steps back down by 3. A small note shows on the player for a few seconds when it goes up. Settings has a reset.
- Stuck loops: on top of the existing 8-reconnects-a-minute limit, a channel that reconnects 12 times in 10 minutes, or never shows video across 3 reconnects in a row, switches to the same channel on another account.

## Polish (October 2026)

- Clean names: provider titles and channel names show as a clean name plus small tags. Quality and language tags (4K, HDR, FHD, HD, RAW, DE, MULTI, US...) come off the ends and off "US|"-style prefixes; symbols and emoji (◉, ✨, ᴿᴬᵂ) go. Tags show under the title on posters and the details page, and next to channel names in Live TV. Capitalization stays as the provider wrote it. Search and sorting still use the raw name.
- Extra buffer counting ignores the first 10 seconds after a channel opens or reconnects, and back-to-back hiccups (within 10 s) count as one stall.
- A channel that answers and then sends nothing three times in a row is treated as down on that account (any account type): straight to a backup, skipped there for 30 minutes.
- Logs never show a working stream link: logins, MACs, and play tokens are masked in the Terminal as well as in the copied log.

## Roadmap to the public release (October 2026)

1. Release setup: test builds as GitHub pre-releases, with working updates.
2. Windows.
3. Skins, the very last thing before the drop: built-in skins, plus making your own by picking colors for the parts we expose, optionally with textures.
4. Public release (2.0.0), plus a final 1.x update that says 2.0 is here, with a download button.

## Releases and updates (October 2026)

- Updates use Sparkle through the auto_updater package. Release builds check quietly when they open and once a day; Settings has Check for updates. When there's a new version, Sparkle shows what's new and asks: install and relaunch, or later. Development builds (flutter run) only check when you press the button.
- The Mac App Sandbox is off, because a sandboxed app can't replace itself (only App Store apps need the sandbox). That moves where macOS keeps the app's data: the database now lives in ~/Library/Application Support/com.blackmango.blackMango, and the release installer copied the existing data there once.
- No paid Apple developer account for now. On first install, macOS Sequoia blocks the app once; people open System Settings > Privacy & Security > Open Anyway. Every release page carries that short guide. Updates afterwards come through Sparkle.
- Downloads: a .dmg to drag into Applications. The updater uses a .zip of the same app, signed with Sparkle's free EdDSA key. The public key is in Info.plist; the private key is in the Mac's Keychain and in the repo's SPARKLE_PRIVATE_KEY secret. Losing it means existing copies can't take updates, so it's backed up in the Keychain.
- Pushing a tag builds everything in GitHub Actions: v2.0.0-beta.1 makes a pre-release (test build), v2.0.0 a final release. The update feed lives on the repo's "updates" branch (appcast.xml), so pre-releases reach testers too.
- Release notes: Claude drafts them in plain language (release-notes/<tag>.md) and Chad approves before tagging.

## Mini player (October 2026)

- Minimize: a button on the mini player shrinks it to a slim bar with the title, play/pause, and close. No video; the sound keeps playing. Works for the in-app card and the floating window (which keeps its bottom-right corner in place). Going back to the full player, or stopping, shows the video again next time.
- Auto-float switch: a button on both the full player and the mini player turns "float when I switch apps" on or off (mango when on). It's the same setting as in Settings.

## Layout (October 2026)

- Movies, Shows, and Live TV stay side by side (list left, details or video right) down to about 620 px wide; they stack only in tiny windows. In a narrow details panel the poster stays beside the title and the text wraps.

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
- Movies and shows (step 2; the menu was later simplified to general groups, see "Category menu"): a category menu next to the account filter, opening on the last one you used (remembered per account). The portal's own "All" category is hidden (it would mean the full crawl). A big category shows its first titles right away and keeps loading the rest in the background. Titles sort A to Z like the rest of the app, so the A-Z bar keeps working. Under "All accounts", Stalker titles appear once their category has been opened or searched. Cached categories refresh after 24 hours on next open, plus a manual refresh. Portal search runs on Enter; local results still filter as you type. Plot, cast, year, and rating are saved with each title so details open instantly. Opening a show loads its first season right away and the others in the background. Movie and episode failover includes Stalker in both directions, same as live.

Category menu (October 2026)
- A small "Categories" button. The menu shows "Everything loaded so far" (every title already cached for the account), then general groups instead of the portal's own dozens of specific categories: New & in cinemas, Top rated, Netflix/Prime/Disney & co, Action & Adventure, Comedy, Horror & Thriller, Drama, Kids & Animation, Documentary, Sci-Fi & Fantasy, Other (only groups that have categories show).
- Groups only; the specific portal categories aren't listed. Picking a group loads every portal category in it, one after another (first titles show right away). It opens on the last group you used; the first time, on the first group.
- The open group shows in the count line ("425 movies · Comedy"), not on the button.

What the movies probe found (October 2026, one German/EU portal)
- Movies and shows are separate types (vod, series), 14 titles per page, with the portal's own "All" category first.
- Each title carries plot, cast, director, genres, year, IMDb rating, and a TMDB poster link, so nothing extra is fetched to open a page.
- Movie links come from create_link (type vod) and, unlike live links, can be reused and seeked (Range works), so resume and the player's own reconnects just work.
- A show's seasons come back in one request (movie_id with season_id 0); each season lists its episode numbers. An episode plays as its season's command plus the episode number. So "first season right away, the rest in the background" isn't needed: all seasons arrive at once.
- The account card shows the portal's totals (its "All" counts); titles are cached as you open categories or search.
- Portal search covers movies and shows.
- Channel switching on its own is fast (about 1 s, even with the old channel still open). The long waits seen in the app came from requests piling up, which the one-connection fix stops; the wait message now just says the provider is starting the channel.

Ready-made channel links (October 2026)
- One portal (NukeTM) lists a ready-made play link, with an old token, as each channel's command. Asking create_link with it returns a link with an empty channel number, and the server resets the connection. Asking by channel number instead ("ffmpeg http://localhost/ch/<id>_") gets a proper link that plays (tested on 4 channels). Playing the listed link directly worked only sometimes (509 on others), so it isn't used.
- So: a command that's already a real link gets asked for by channel number; any link that still comes back without a channel number gets one more try by number.

Dead channels (October 2026)
- Some of one portal's channels sit on a broken stream server: it answers after ~21 s with no video, and any new link right after gets HTTP 407 (a short lockout). Confirmed outside the app.
- So a Stalker channel that answers with no video, or with 407, counts as down on that account: the app stops asking that server (more links only extend the lockout) and goes straight to the same channel on another account. It skips that channel on that account for 30 minutes; with no backup anywhere it tries anyway.
- A Stalker channel gets 12 seconds to answer and send its first video (working ones take 1 to 5). No answer in time counts as down too, with the same 30-minute skip.

One connection per account
- What we saw: a Stalker MAC gets one stream at a time. While it's busy, the stream server parks new requests and answers ~40-48 s later, often with 509 ("too many connections"). Requests the app had walked away from sat in that queue, and the player's own quick retries joined it.
- So: one request per Stalker account at a time (a new channel, or the player's own retry, closes the older request instead of queueing behind it), and anything you walked away from is cancelled when you pick something else.
- The player waits up to a minute for a Stalker server instead of retrying every 15 s. After about 6 s it says it's waiting for the provider to free up the connection. If nothing comes, it falls back to the same channel on your other accounts.
- Flipping through a Stalker account's channels: the portal is asked only once you stay on one for about a second.
- Stalker live requests don't send a Range header (live streams can't seek; the plain request is what works).
- A 509 counts as "busy", not "server down".
- Smart paste: with several URLs, the one labeled Portal or Panel wins, else the first ending in /c/ or portal.php. With several MACs, offer one account each after a confirm.
- Smart paste details (October 2026): it reads the paste as soon as you paste (Detect stays as a backup). It copes with fancy-font labels, emoji and box-drawing decorations, and values run together ("link,MAC"). Several MACs become one account each, named like "amster9216.pro · E0:67", loaded one after another. A Stalker paste that also carries an M3U/Xtream login stays Stalker, with a one-click "Use the M3U login instead": usually the better choice in Black Mango (the whole catalog loads at once), but it's the same subscription and connection limit, so it's one or the other. Afterwards it says what it found and what it ignored ("Found: portal, 2 MACs. Ignored: expiry date, 1 other link.").
- Credit for stalkerhek: README plus file headers.
