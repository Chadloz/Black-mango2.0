# Skin drops: how to run one

Black Mango checks the drop list shortly after it opens and every 6 hours. Anyone with the app
open during a drop's window collects its pack for good, and a gift box shows it to them.

## The pieces

- **Pack files** live in `assets/packs/<pack id>.json`. A pack has a name, the decorations, logo and
  title font it uses (by name, from what's built into the app), and its skins' colors. Keep these:
  they're the record of every pack, and any of them can drop again later.
- **The drop list** is `drops/drops.json`. Each drop says which pack, and from which day through
  which day (people's own local days).
- Pushing either one to main runs the **Skin drops** workflow, which checks them, puts each drop's
  pack file inside the list, and publishes it next to the update feed. No app update needed.

## A holiday or surprise drop

Add a line to `drops/drops.json`:

```json
{"id": "surprise-mango-week", "name": "Surprise!", "pack": "thanksgiving-2026", "start": "2026-11-03", "end": "2026-11-04"}
```

The window is whatever you set: one day, a weekend, a month. A drop can reuse an old pack (people
who already have it just don't get it twice) or a new pack file.

A new pack that only changes colors (using decorations, a logo and a font the app already has)
works in the app people already have. New decorations need an app update first.

## A giveaway

Make the line with the tool, so the code itself never goes in the public repo:

```bash
python3 tool/giveaway_code.py MANGOGIFT thanksgiving-2026 2026-11-20 2026-11-22
```

Paste the line it prints into the `drops` list, push, then hand out the code. People type it in
Settings > Skins > Redeem a code while the window is open. Codes ignore capitals and spaces.

Exclusive is a soft promise: the app is open source, and a code can be passed around. That's fine
for a perk.
