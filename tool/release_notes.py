#!/usr/bin/env python3
"""Prints a release's notes (release-notes/<tag>.md) plus the first-install guide, for the
GitHub Release page. Usage: python3 tool/release_notes.py v2.0.0-beta.1"""
import os, sys

GUIDE = """
## Installing on a Mac

1. Download the **.dmg** below, open it, and drag **Black Mango** into **Applications**.
2. Open Black Mango. The first time, macOS says it can't check the app and won't open it. Click **Done**.
3. Open **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to Black Mango. Confirm with your Mac password.

You only do this once. After that, Black Mango opens normally and updates install from inside the app.
"""

tag = sys.argv[1] if len(sys.argv) > 1 else ''
path = os.path.join('release-notes', tag + '.md')
notes = open(path, encoding='utf-8').read().strip() if os.path.exists(path) else 'Fixes and improvements.'
print(notes + '\n' + GUIDE)
