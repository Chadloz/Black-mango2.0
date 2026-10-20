#!/usr/bin/env python3
"""Adds a release to Black Mango's update feed (appcast.xml), newest first: one item per platform.
Mac items are read by Sparkle (EdDSA signature), Windows items by WinSparkle (DSA signature);
each enclosure says which system it's for (sparkle:os), so neither updater picks the other's file.
Run by the release workflow; plain Python, no extra packages."""
import argparse, datetime, html, os, re
from email.utils import format_datetime

HEAD = ('<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n'
        '  <channel>\n'
        '    <title>Black Mango</title>\n')
TAIL = '  </channel>\n</rss>\n'


def md_to_html(md):
    """Just enough Markdown for release notes: headings, bullet lists, bold, paragraphs."""
    out, in_list = [], False

    def inline(t):
        t = html.escape(t)
        return re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', t)

    for raw in md.splitlines():
        line = raw.rstrip()
        bullet = re.match(r'^\s*[-*]\s+(.*)', line)
        if bullet:
            if not in_list:
                out.append('<ul>')
                in_list = True
            out.append('<li>%s</li>' % inline(bullet.group(1)))
            continue
        if in_list:
            out.append('</ul>')
            in_list = False
        if not line.strip():
            continue
        h = re.match(r'^(#{1,3})\s+(.*)', line)
        if h:
            level = min(len(h.group(1)) + 1, 4)
            out.append('<h%d>%s</h%d>' % (level, inline(h.group(2)), level))
        else:
            out.append('<p>%s</p>' % inline(line))
    if in_list:
        out.append('</ul>')
    return '\n'.join(out)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--feed', required=True)
    p.add_argument('--version', required=True)      # 2.0.0-beta.1
    p.add_argument('--build', required=True)        # always increasing (the workflow run number)
    p.add_argument('--url', required=True)          # the release's .zip
    p.add_argument('--os', choices=['macos', 'windows'], default='macos')
    p.add_argument('--signature', default='')       # Mac: sign_update output, sparkle:edSignature="..." length="..."
    p.add_argument('--dsa-signature', default='')   # Windows: base64 DSA signature of the installer
    p.add_argument('--length', default='')          # Windows: installer size in bytes
    p.add_argument('--notes', default='')
    p.add_argument('--min-os', default='12.0')
    a = p.parse_args()

    if a.os == 'macos':
        sig = re.search(r'edSignature="([^"]+)"', a.signature)
        length = re.search(r'length="(\d+)"', a.signature)
        if not sig or not length:
            raise SystemExit('Could not read the update signature: %r' % a.signature)
        sig_attr, size = 'sparkle:edSignature="%s"' % sig.group(1), length.group(1)
    else:
        if not a.dsa_signature or not a.length.isdigit():
            raise SystemExit('The Windows item needs --dsa-signature and --length.')
        sig_attr, size = 'sparkle:dsaSignature="%s"' % a.dsa_signature, a.length
    notes = open(a.notes, encoding='utf-8').read() if a.notes and os.path.exists(a.notes) else 'Fixes and improvements.'
    if a.os == 'macos':
        extra = '      <sparkle:minimumSystemVersion>%s</sparkle:minimumSystemVersion>\n' % a.min_os
        enclosure_extra = 'sparkle:os="macos"'
        title = 'Black Mango %s' % html.escape(a.version)
    else:
        # WinSparkle compares this with the app's own file version ("2.0.0+N"), and runs the
        # installer quietly; the installer reopens Black Mango when it's done.
        extra = ''
        enclosure_extra = ('sparkle:os="windows" sparkle:version="%s" sparkle:shortVersionString="%s" '
                           'sparkle:installerArguments="/SILENT /SP- /SUPPRESSMSGBOXES /NORESTART"'
                           % (html.escape(a.build), html.escape(a.version)))
        title = 'Black Mango %s for Windows' % html.escape(a.version)
    item = (
        '    <item>\n'
        '      <title>%s</title>\n'
        '      <pubDate>%s</pubDate>\n'
        '      <sparkle:version>%s</sparkle:version>\n'
        '      <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n'
        '%s'
        '      <description><![CDATA[%s]]></description>\n'
        '      <enclosure url="%s" length="%s" type="application/octet-stream" %s %s/>\n'
        '    </item>\n'
    ) % (title, format_datetime(datetime.datetime.now(datetime.timezone.utc)), html.escape(a.build),
         html.escape(a.version), extra, md_to_html(notes), html.escape(a.url), size, enclosure_extra, sig_attr)

    if os.path.exists(a.feed):
        feed = open(a.feed, encoding='utf-8').read()
        # Older items were all Mac ones, from before the Windows version: mark them so.
        feed = re.sub(r'<enclosure (?![^>]*sparkle:os=)', '<enclosure sparkle:os="macos" ', feed)
        marker = '    <title>Black Mango</title>\n'
        at = feed.find(marker)
        if at < 0:
            raise SystemExit('The existing feed has an unexpected layout.')
        at += len(marker)
        feed = feed[:at] + item + feed[at:]
    else:
        feed = HEAD + item + TAIL
    with open(a.feed, 'w', encoding='utf-8') as f:
        f.write(feed)
    print('Feed updated: %s for %s (build %s)' % (a.version, a.os, a.build))


if __name__ == '__main__':
    main()
