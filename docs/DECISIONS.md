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

## Lists keep your spot (October 2026)

- Live TV, Movies and Shows remember where you scrolled. Shrinking to the floating player or switching layouts no longer resets the list; only your own scrolling moves it.
- Small Top and Bottom buttons sit at the bottom-right of each list. Shortcuts: Home (top), End (bottom), and B to go back to where you were before the last jump (press again to swap back). The arrow keys stay for moving around. All three can be changed in Settings like the other shortcuts.

## Skins (October 2026)

- Every color comes from a skin's 7 slots: background, panels, raised panels, borders, accent (Black Mango's orange), text, and dim text. A skin can also bring its own logo, title font and decorations. Picked any time in Settings > Skins (Appearance until test build 7), where each skin's card is drawn in its own colors; the whole app repaints right away without losing your place. Player icons stay white for readability; progress bars and highlights use the skin's accent. (Test build 7: player buttons became their own color slot, white unless a custom skin changes it.)
- First skins (test build 6): Black Mango (the default) and a Halloween pack of four: Pumpkin Patch (pumpkin orange on near-black purple), Witching Hour (witch purple on indigo), Blood Moon (crimson on black-red), Graveyard Fog (toxic green on dark green-gray).
- Every Halloween skin has: the jack-o'-lantern mango logo (the scary face, carved into the dark skin and glowing), two lit pumpkins beside it with a candle flicker, bats in the top bar, cobweb corners, a faint fog along the bottom, the dripping Nosifer font for the wordmark and screen titles (SIL Open Font License, bundled), and a cute sheet ghost that floats up from a random corner and says "Boo! <account> added" when you add an account.
- Custom skins (test build 7), settled up front:
  - Skins has its own page, Settings > Skins, so Settings stays short. It holds the built-in skins, My skins, and Make your own.
  - Make your own starts from a copy of your current skin or from Black Mango. The editor puts the color controls beside a small preview, and the whole app follows as you pick (nothing is kept until Save; Cancel puts your skin back).
  - Simple mode: background, panels and accent; the rest (raised panels, borders, text, dim text) is worked out from those. Advanced: all 7 slots plus a new 8th, the player buttons over the video (white by default, so built-in skins look the same).
  - Picking a color: a color wheel (hue ring around a saturation/brightness square, our own widget: FlexColorPicker 4 needs the new material_ui packages, and the wheel is small), a hex code box, and swatches from the built-in skins.
  - Eyedropper, anywhere on screen (part 2): Mac uses Apple's NSColorSampler (the system color panel's magnifier; no screen-recording permission, works outside the window). Windows has no system sampler and no Flutter package does this on both systems, so Windows copies the screen Black Mango is on (GDI BitBlt, top-down BGRA), the window goes full screen showing that frozen copy, a magnifier (11 x 11 pixels) follows the mouse, click to pick, right-click, Esc or Cancel to stop, and the window goes back as it was. Native halves: macos/Runner/MainFlutterWindow.swift and windows/runner/flutter_window.cpp, channel "blackmango/eyedropper".
  - Skin from a picture (part 2): pick a picture; its six main colors come from k-means on about 6,000 sampled pixels. The suggestion is always a dark skin, to suit the app: background and panels from the darkest color that covers a fair part of the picture (kept dark), the accent from the most vivid color (weighted by how much of the picture it covers), the rest worked out as in Simple mode, then made readable. The picture stays in the editor to click any color out of it.
  - Textures per area (October 24, replaces the single texture below): background, panels (top bar, sidebar, the bar under the player), cards (account cards, the tiles behind posters and logos), search boxes, and accent highlights (the selected category and sidebar item, the playing channel, filled buttons). Each area has its own texture, strength, size (50% to 300%) and tint (the light specks take the tint color; picked with the same wheel, hex box, swatches and eyedropper as colors). "Use this texture on every area" copies one to all. Text, dim text, borders and player buttons are letters and lines, so they take no texture. Menus keep a flat color (Flutter's menus only take a color). Category pills are now drawn by hand instead of Flutter's ChoiceChip, so the selected one can carry a texture. The readability check covers textures: text has to stay readable on both the lighter and darker specks (roughly a third of the strength on average), and Auto-fix turns the texture down until it does. Skin files carry each area's picture once ("pictures": {"p1": ...}); older single-texture skins become background + panels.
- Textures (part 2): built-in tiles (Grain, Carbon fiber, Brushed metal, Paper; 256 px seamless PNGs that are white and black specks with transparency, so they lighten and darken whatever color is under them and work on any skin) or your own picture, with a strength slider (default 40%). They show on the window background, top bar and sidebar; cards, lists and menus stay solid so text stays readable, and nothing is drawn over the video. Your own picture either fills the background (a photo) or repeats as a pattern on the background and panels. Pictures (PNG, JPEG, GIF, WebP, up to 12 MB) are copied into the app's support folder under skins/; ones no saved skin uses are cleaned up at startup and after a delete.
  - Readability check on save, WCAG contrast: text 4.5 against the background and panels, dim text 3, highlights 3 against the background, player buttons 3 against black. If something fails: Cancel, Keep my colors, or Auto-fix (changes only the failing colors, lightness first, keeping the hue, then saves). The editor marks weak colors as you go.
  - Halloween extras are switches on any skin: decorations (cobwebs, fog, bats, pumpkins, the Boo! ghost), the dripping title font, and the jack-o'-lantern logo.
  - Buttons filled with the accent use black text on bright accents and white on dark ones.
  - My skins: as many as you like, kept in settings (so backups carry them). Each can be edited, duplicated, copied as a skin code, saved as a file, or deleted. Built-in skins can be copied to edit, or shared the same ways.
  - Skin files: one skin per .blackmango-skin.json file (format "black-mango-skin", version 1): name, 8 colors as #RRGGBB, and the three Halloween switches. Never file paths, so a shared skin can't point at anything on your computer. Missing colors fall back to Black Mango's.
  - Skin codes: the same content, gzipped and base64url, after "BMSKIN1:", on one line, to paste anywhere. Settings > Skins > Paste skin code reads the clipboard, and Add Account's quick paste spots a skin code and offers to add it. A built-in texture fits in a code; your own picture travels only in a skin file (base64, inside the JSON), and only your own saved skins may point at a picture file, so a shared file or code can never name a path.

## Skin drops and community (planned, October 2026)

Settled (October 24): beta.7 waits until the skins are done, so there aren't lots of small updates. It ships with the editor, the drop checker, and two holiday drops: Thanksgiving and Christmas, both with their own decorations. Anyone who opens the app during a drop's window collects it (new installs count too). Drops can be collected from November 2026 through January 15, 2027. Collected exclusives can't be shared as a code or file; a copy you edit keeps the colors only. A drop arrives with a reveal (Use it now / Later) and lives in My skins with an exclusive badge. The drop feed sits next to the update feed on GitHub (the updates branch).

Built (test build 7):
- Windows run back to back: Thanksgiving from November 1 through Thanksgiving Day, Christmas from the day after Thanksgiving through December 25, then New Year's from December 26 (more holidays later). Each pack can only be collected inside its own window.
- The drop list is drops/drops.json on main. The Skin drops workflow publishes it next to the update feed (updates/drops.json) whenever it changes; the release workflow only touches appcast.xml, so they don't collide. The app checks shortly after opening and every 6 hours, takes the time from the feed server's Date header (so a wrong computer clock doesn't matter much), and keeps the last list for when it's offline.
- A pack's skins, decorations, logo and title font ship inside the app (they're code), switched off until collected. The feed only says when each pack can be collected, so dates can change without an update; colors-only drops could later come entirely from the feed.
- Collected: saved in settings (skins.collected), so backups keep them. Listed under My skins with a star and the drop's name. No skin code or file for them; "Make a copy to edit" keeps the colors only (no decorations, logo or title font). Copies are never exclusive.
- The reveal: a gift box drops in, wiggles, pops its lid, and the pack's skins come out. Use it now switches to the first one (or click any of them); Later keeps them in My skins. It waits if the window is a floating player at the time. Reduced motion skips the animation.
- Debug builds (flutter run) have test buttons at the bottom of Settings > Skins: drop any pack now, or forget collected packs.
- Thanksgiving 2026 pack: Harvest (pumpkin orange on deep brown), Autumn Leaves (red-orange on dark olive), Cranberry & Gold (gold on dark plum). The mango turkey logo (a fan of tail feathers in rings of cream, red-brown, orange and brown behind the mango), Berkshire Swash for titles (SIL Open Font License, bundled), leaves drifting down behind the content (behind, so never over text panels or the video; still with reduced motion), a harvest in the top bar (a bundle of wheat, two acorns, an orange, a white and a green pumpkin, and a pumpkin pie), and a turkey who struts in and says "Gobble! <account> added" when you add an account.
- Pack files (October 24): every drop pack is a file, assets/packs/<id>.json (format "black-mango-pack"): its name, the decorations, logo and title font it uses by name (built into the app), and each skin's colors (and built-in textures). They're bundled with the app and also carried inside the published drop list, so a colors-only pack can drop to the app people already have. Unknown names are left out (an older app shows the colors without newer decorations). Collected packs are saved as they were when collected. Chad keeps the pack files; any pack can drop again later.
- Drop list v2: each drop names its pack and its window (any length: holidays, surprise drops). A drop with a "code" is a giveaway: only people who type the code in Settings > Skins > Redeem a code collect it, while its window is open. The repo is public, so only the code's hash goes in the list (tool/giveaway_code.py; capitals and spaces ignored). How-to: docs/DROPS.md.
- New Year's pack: a December update, not beta.7.
- Christmas 2026 pack (assets/packs/christmas-2026.json, drops November 27 through December 25): Classic Christmas (red on deep green-black), Snowy Night (icy blue on navy, with a faint icy grain on the background) and Candy Cane (red on charcoal). The mango in a Santa hat holding a candy cane; Mountains of Christmas for titles (Apache License 2.0, bundled with its license); snow falling behind the content (never over text panels or the video); snow piled along the top of the top bar and twinkling string lights along its bottom, after the logo; a winter scene in the top bar (a snowman in a scarf and beanie, an elf of our own with a present, and a reindeer; no real person's likeness, which would need permission, and no red glowing nose, which is a trademarked character); frost in the window's top corners and bottom-left corner (none reach the video); and a present that pops open and says "Ho ho ho! <account> added" when you add an account.

The original plan, for the record (items 1 to 4 are now part of beta.7):
1. Holiday drops. A small skins feed (a JSON file in the repo, like the update feed), checked when the app opens and once a day. Each drop is a skin plus a date window; open the app during the window and the skin is saved for good, labeled with its name and year (for example "Christmas 2026"), with a little reveal. My skins becomes your saved skins: made, imported or collected. Backups keep them. Proposed: the receiver ships in 2.0.0, since a drop only reaches versions that know how to check for it (Chad to confirm).
2. Exclusive is soft in an open-source app: anyone determined can rebuild a skin from the source, and that's fine for a perk. Collected exclusives can't be copied as a skin code or file; a copy you edit keeps the colors but not the exclusive extras.
3. New colors can drop any time through the feed. New decorations (snow, hearts) are code, so they ship in an update a few weeks ahead, switched off until their window opens.
4. First drop: Christmas (Thanksgiving only if 2.0 is out a week before, colors only). Then New Year's, Valentine's, St. Patrick's, 4/20, the Fourth of July, Halloween 2027.
5. Community gallery, curated: browse, preview live and add skins on the Skins page. Submitting sends the skin code to a GitHub form (needs a free GitHub account, no server to run); Chad approves; it shows up for everyone, credited to its maker. Holiday contests can pick the next drop. Colors and built-in textures first; pictures only once there's moderation for them.
6. Marketplace, only if the community grows: upload from the app, likes, download counts, reporting. Needs a server, sign-in, moderation and a privacy policy. Keep it free.

## Security hardening (October 2026)

A friend's review (an analysis tool run on the installed Windows app) and a check against the code. Chad's call: build all of it into test build 7, since it's on hold anyway.

Built:
- The video engine never hands links to yt-dlp or youtube-dl (mpv option ytdl=no, set for every stream). IPTV never needs it, and it would let a provider's link start another program if yt-dlp happens to be installed.
- The local relay: links are random 128-bit tokens instead of counting up (/r/0.ts, /r/1.ts were easy to guess once the port was found); requests must be addressed to 127.0.0.1 (blocks DNS-rebinding tricks); requests that browsers mark (Origin or Sec-Fetch-Site headers) are refused. The video engine sends neither.
- Open in VLC only passes links with a stream scheme (http, https, rtmp, rtmps, rtsp, rtp, udp, mms). It already started VLC directly with the link as its own argument (no shell); this closes the one gap, a link starting with a dash being read as a VLC option.
- Settings > App updates: "Check for updates automatically" (on by default). Off: only Check for updates checks. Updates were already signed and the app always asks before installing; the installer's /SILENT flags only skip its own screens after you click Install.
- Release workflow: the job that uses the signing keys runs in a "release" environment (add a required reviewer in repo Settings > Environments so every release waits for Chad's approval, and move the two signing secrets into that environment). Every release now has SHA256SUMS.txt and GitHub build attestations (actions/attest-build-provenance) proving each file was built by the workflow from the public code.
- Dependabot (monthly): pull requests when packages (media_kit and its libmpv included) or GitHub Actions have new versions.
- SECURITY.md: what the app connects to, what it keeps, how updates are protected, how to report a problem (privately, through GitHub's Security tab).

Found while writing SECURITY.md (not in the review): logins live unencrypted in the app's settings file (moved out of the Keychain because an unsigned app made macOS ask for the password over and over), and backups include them. SECURITY.md says so plainly.

Chad's side (no code): a passkey or security key for GitHub sign-in, recovery codes kept offline, old access tokens and unused authorized apps removed; repo rules so only Chad can create v* tags; the release environment's reviewer rule; Dependabot alerts and private vulnerability reporting turned on.

Later, before or around 2.0:
- Code signing: Apple Developer ID and notarization (Apple's developer program, $99 a year); Windows through Azure Artifact Signing (formerly Trusted Signing, $9.99 a month, US/Canada/Europe, works from GitHub Actions). Removes the "unknown developer/publisher" warnings.
- With a stable Apple signature, logins can go back to encrypted system storage (Keychain on Mac, Credential Manager on Windows) without password prompts; optional password-protected backups.
- macOS hardened runtime (needed for notarization anyway).

## Mouse scrolling on sideways rows (October 2026)

- A mouse wheel only scrolls up and down, and Flutter doesn't let a mouse drag a list (only touch and trackpads, since Flutter 2.5), so sideways rows only moved with a trackpad. Every sideways row now has a scrollbar along its bottom you can drag or click along.
- Category strips (Live TV, Movies, Shows) and the Favorites filter: the wheel slides them anywhere over the row. Home's rows sit inside a page that scrolls up and down, so there the wheel scrolls the page, and only slides a row while the pointer is over its scrollbar. Shift+wheel and sideways wheels work as before.

## Smoother live TV (October 2026)

- Jumps and blocks (October 2026, test build 4): some providers hang up every few seconds during busy events and come back at "live", so footage is lost and the next frames refer to pictures we never got. Black Mango now tells a clean reconnect (the provider replays a little, so nothing is lost) from one that lost footage. After a loss, or when the provider restarts its clock, it holds the last clean picture (sound keeps going) until the next full frame, so there are no blocks. The log says how many seconds were lost.
- If footage gets lost 6 times in 2 minutes, a note says the provider keeps cutting the stream, and Black Mango switches to the same channel on another account (skipping this one there for 30 minutes). With no backup, it keeps playing with just the note. Clean reconnects don't count.
- Bigger cushion for channels that keep reconnecting (test build 5): 4 provider drops in 2 minutes marks a channel (remembered, like its extra buffer), and it can then grow past 15 seconds in steps of 5, up to 30. It still only grows when it stalls. Being further behind live and a slower start are the price; Settings reset clears it.
- Same server first (test build 5): providers run a pool of stream servers whose clocks don't match, and asking the provider's address again on a reconnect can land on a different one (the log says "provider restarted its clock"), which makes the picture jump. The relay now remembers the server the provider sent it to and reconnects there first. Right after a drop, servers often still count the old connection and answer busy (509, 407, 403), so it gives the same server 3 tries 1.5 s apart; on any other refusal, or no answer within 6 seconds, it asks the provider again. A provider whose servers answer busy all 3 times is noted (until the app restarts) and from then on goes straight back to the provider, since the waiting only made each reconnect slower (Phantom during a busy game: 509 every time). The log notes when the provider moves us to another server, and a reconnect on a different server always holds the picture until a full frame (its frames don't build on the old server's), even when the timestamps line up.
- HLS first (test build 5): after 3 jumps in 2 minutes on an Xtream channel, Black Mango switches that channel to its HLS version (.m3u8) on the same account and remembers it for that channel. HLS comes in chunks, so a dropped connection doesn't lose footage. A short note says so. If HLS doesn't show a picture within 12 seconds (some providers' HLS loads its list and then fails on every chunk), it goes back to the regular stream and doesn't try HLS on that account for a week. If HLS still struggles, the usual protections (extra buffer, stuck-loop switch to another account) take over. Settings > Fixes for flaky channels resets both the extra buffers and the HLS choices.
- Stalker logins on Windows send the PC's real timezone (from Windows' zone names, or the UTC offset), not UTC.

- Extra buffer for flaky channels: a live channel that stalls twice within 5 minutes gets 3 more seconds of cushion, up to 15 seconds in all (your "Buffer before a channel starts" setting plus its extra). It's remembered per channel on each account, even after restarting, and takes effect at the next rebuffer. After 30 minutes of smooth watching it steps back down by 3. A small note shows on the player for a few seconds when it goes up. Settings has a reset.
- Stuck loops: on top of the existing 8-reconnects-a-minute limit, a channel that reconnects 12 times in 10 minutes, or never shows video across 3 reconnects in a row, switches to the same channel on another account.

## Polish (October 2026)

- Clean names: provider titles and channel names show as a clean name plus small tags. Quality and language tags (4K, HDR, FHD, HD, RAW, DE, MULTI, US...) come off the ends and off "US|"-style prefixes; symbols and emoji (◉, ✨, ᴿᴬᵂ) go. Tags show under the title on posters and the details page, and next to channel names in Live TV. Capitalization stays as the provider wrote it. Search and sorting still use the raw name.
- Extra buffer counting ignores the first 10 seconds after a channel opens or reconnects, and back-to-back hiccups (within 10 s) count as one stall.
- A channel that answers and then sends nothing three times in a row is treated as down on that account (any account type): straight to a backup, skipped there for 30 minutes.
- Logs never show a working stream link: logins, MACs, and play tokens are masked in the Terminal as well as in the copied log.

## Roadmap to the public release (October 2026)

1. Release setup: test builds as GitHub pre-releases, with working updates.
2. Windows (first test build: v2.0.0-beta.3).
3. Skins, the very last thing before the drop: built-in skins (the Halloween pack came first, in test build 6), plus making your own by picking colors for the parts we expose, optionally with textures.
4. Public release (2.0.0), plus a final 1.x update that says 2.0 is here, with a download button.

## Releases and updates (October 2026)

- Updates use Sparkle through the auto_updater package. Release builds check quietly when they open and once a day; Settings has Check for updates. When there's a new version, Sparkle shows what's new and asks: install and relaunch, or later. Development builds (flutter run) only check when you press the button.
- The Mac App Sandbox is off, because a sandboxed app can't replace itself (only App Store apps need the sandbox). That moves where macOS keeps the app's data: the database now lives in ~/Library/Application Support/com.blackmango.blackMango, and the release installer copied the existing data there once.
- No paid Apple developer account for now. On first install, macOS Sequoia blocks the app once; people open System Settings > Privacy & Security > Open Anyway. Every release page carries that short guide. Updates afterwards come through Sparkle.
- Downloads: a .dmg to drag into Applications. The updater uses a .zip of the same app, signed with Sparkle's free EdDSA key. The public key is in Info.plist; the private key is in the Mac's Keychain and in the repo's SPARKLE_PRIVATE_KEY secret. Losing it means existing copies can't take updates, so it's backed up in the Keychain.
- Pushing a tag builds everything in GitHub Actions: v2.0.0-beta.1 makes a pre-release (test build), v2.0.0 a final release. The update feed lives on the repo's "updates" branch (appcast.xml), so pre-releases reach testers too.
- Release notes: Claude drafts them in plain language (release-notes/<tag>.md) and Chad approves before tagging.
- The cloud build re-signs the whole app with a free ad-hoc signature (codesign --force --deep --sign -) and verifies it. Without that, a downloaded copy showed "damaged and can't be opened" (test build 1). Release pages also carry the xattr fallback line.
- Moving data out of the sandbox (one time, Chad's Mac only): the library came over, but the saved passwords didn't; re-adding the Xtream accounts fixed it. New installs start fresh, so no one else is affected.
- Live channels go to the player as open-ended streams (no length or range headers), even when a provider serves a looping file with a fixed size.

## Windows (October 2026)

- One tag builds both: a Windows job makes the installer, then the Mac job signs everything and publishes a single release with the .dmg, the Mac update .zip, and the Windows Setup .exe.
- The installer (Inno Setup) installs for the current user only: no admin password, and updates install quietly. Start menu entry, uninstaller in Settings > Apps, and a desktop shortcut checkbox (checked by default). It includes the Visual C++ runtime files Flutter apps need.
- No code signing on Windows for now: the first run shows "Windows protected your PC" > More info > Run anyway, once. The release page explains it.
- Updates use WinSparkle (through the same updater package), reading the same feed. WinSparkle 0.8.1 only checks DSA signatures, so Windows has its own DSA key: the public half is built into the app (windows/runner/resources/dsa_pub.pem), the private half is on Chad's Mac (~/.black-mango-sparkle/dsa_priv.pem) and in the WINSPARKLE_DSA_PRIVATE_KEY secret. Every feed item says which system it's for (sparkle:os), so neither updater picks up the other's file. When a Windows update is ready, the app closes itself, the installer runs quietly, and it reopens Black Mango.
- Keyboard shortcuts are single keys, so they work the same on Windows; anything that's Cmd on the Mac is Ctrl on Windows. Open in VLC looks for VLC under Program Files.

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
