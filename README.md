# Black Mango

A free, open source IPTV player for Mac, Windows, and Linux, built on Flutter and mpv.

Black Mango 2.0 is a ground-up rebuild of the original Electron app. mpv and FFmpeg handle playback, so formats like Dolby Digital, Dolby Digital Plus, HEVC, and raw MPEG-TS streams play natively.

## Status

Early development. Not ready for daily use yet. The 1.x Electron app lives at github.com/Chadloz/darkflix.

## Stack

- Flutter (Dart) for the UI and app logic
- media_kit (libmpv + FFmpeg) for playback
- Rust only where Dart isn't fast enough

## License

GPL-3.0. See LICENSE.
