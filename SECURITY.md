# Security

Black Mango is a free, open-source IPTV player. This page says plainly what it connects to, what
it keeps on your computer, how updates are protected, and how to report a problem.

## What it connects to

- **Your IPTV providers**, using the accounts you add. Streams, channel lists, channel logos and
  TV guides come from them (logos and streams can sit on other servers the provider points to).
- **Free channel lists you choose to add** (Add Account > Free channels): public lists such as
  iptv-org, Free-TV and APSATTV, and the streams and logos those lists point to.
- **GitHub**, to check for app updates and holiday skin drops
  (`raw.githubusercontent.com/Chadloz/Black-mango2.0/updates/...`).

Nothing else. No ads, no analytics, no accounts with us, and nothing is sent about what you watch.

## What it keeps on your computer

- Your settings, favorites, history and skins.
- **Your IPTV logins, in Black Mango's own settings file.** They aren't encrypted there, so
  anything running under your user account could read them. (They were moved out of the macOS
  Keychain because the app isn't Apple-signed yet, which made macOS ask for your password over
  and over. Encrypted storage comes back once the app is signed.)
- **Backups include your logins** so a restore works. Keep backup files private.
- A local relay on `127.0.0.1` (a random port, only while the app is open) that hands live
  channels to the video player. It answers only the player on your own computer: links are random
  and unguessable, and requests from web pages are refused.

## Updates

- Every release is built by GitHub Actions from the public code in this repository, not on
  anyone's own computer.
- Each update is signed (Sparkle EdDSA on Mac, WinSparkle DSA on Windows), and the app checks the
  signature before offering it. A website can't fake an update.
- The app always asks before installing. You can turn off automatic checks in
  Settings > App updates.
- Each release lists every file's SHA-256 in `SHA256SUMS.txt`, and GitHub can confirm a download
  was built by this repository's release workflow:
  `gh attestation verify <file> --repo Chadloz/Black-mango2.0`
- The update channel's trust rests on the maintainer's GitHub account and signing keys, which are
  kept as protected GitHub secrets.
- Not yet: Apple notarization and a Windows publisher signature. Until then, macOS and Windows
  show an "unknown developer" or "unknown publisher" warning the first time.

## Streams

Like every video player, Black Mango decodes video from sources it doesn't control. It plays them
with mpv (libmpv), kept up to date; the player never hands links to other programs such as
yt-dlp, and "Open in VLC" only passes real stream links.

## Reporting a problem

Please report security issues privately: on GitHub, open this repository's Security tab and
choose "Report a vulnerability". Please don't post details in a public issue first.
