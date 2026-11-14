/// Free public channel packs. Black Mango only links to these lists where they live; it never
/// copies them. Each was checked from a US connection in November 2026 (test build 8): lists
/// that had closed or whose channels no longer answered were dropped or pointed at a working
/// source. A pack you've added keeps its id, so a new address here reaches it at its next refresh.
class FreePack {
  final String id;
  final String name;
  final String desc;
  final String url;
  final String icon;
  const FreePack(this.id, this.name, this.desc, this.url, this.icon);
}

const _gen = 'https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists';

const freePacks = [
  FreePack('iptv-org-all', 'IPTV-Org (All)', '11,000+ channels, 100+ countries. Updated daily by bot.',
      'https://iptv-org.github.io/iptv/index.m3u', '📡'),
  FreePack('iptv-org-us', 'IPTV-Org US Only', 'US channels only from iptv-org.',
      'https://iptv-org.github.io/iptv/countries/us.m3u', '🇺🇸'),
  FreePack('iptv-org-news', 'IPTV-Org News', 'News channels worldwide.',
      'https://iptv-org.github.io/iptv/categories/news.m3u', '📰'),
  FreePack('iptv-org-sports', 'IPTV-Org Sports', 'Sports channels worldwide.',
      'https://iptv-org.github.io/iptv/categories/sports.m3u', '⚽'),
  FreePack('iptv-org-movies', 'IPTV-Org Movies', 'Movie channels worldwide.',
      'https://iptv-org.github.io/iptv/categories/movies.m3u', '🎬'),
  FreePack('free-tv', 'Free-TV Curated', '2,000+ free channels by country. No adult. HD preferred.',
      'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8', '📺'),
  FreePack('pluto', 'Pluto TV', 'Pluto TV US: about 450 channels.', '$_gen/plutotv_us.m3u', '🪐'),
  FreePack('samsung', 'Samsung TV Plus', 'Samsung TV Plus US: about 590 channels.', '$_gen/samsungtvplus_us.m3u', '🖥️'),
  FreePack('roku', 'Roku Channel', 'The Roku Channel: about 250 channels.', '$_gen/roku_all.m3u', '📱'),
  FreePack('tubi', 'Tubi TV', 'Tubi live channels: about 175.', '$_gen/tubi_all.m3u', '🍿'),
  FreePack('vizio', 'Vizio WatchFree', 'Vizio WatchFree+: about 480 channels.', 'https://www.apsattv.com/vizio.m3u', '📻'),
  FreePack('xumo', 'XUMO', 'Xumo Play: about 390 channels.', 'https://www.apsattv.com/xumo.m3u', '📲'),
  FreePack('lg', 'LG Channels', 'LG Channels, every country: about 1,300 channels.', 'https://www.apsattv.com/lg.m3u', '🌎'),
  FreePack('lg-us', 'LG Channels US', 'LG Channels, US only: about 460 channels.', 'https://www.apsattv.com/uslg.m3u', '🇺🇸'),
  FreePack('tclplus', 'TCL Plus', 'TCL Plus: about 490 channels.', 'https://www.apsattv.com/tclplus.m3u', '📡'),
  FreePack('tcl', 'TCL TV', 'TCL TV: about 590 channels.', 'https://www.apsattv.com/tcl.m3u', '📺'),
  FreePack('vidaa', 'Vidaa', 'Vidaa (Hisense TVs): about 790 channels.', 'https://www.apsattv.com/vidaa.m3u', '🖥️'),
  FreePack('localnow', 'Local Now', 'Local Now: about 450 channels, heavy on local news.', 'https://www.apsattv.com/localnow.m3u', '📰'),
  FreePack('tablo', 'Tablo', 'Tablo: about 165 channels.', 'https://www.apsattv.com/tablo.m3u', '📻'),
];

/// The pack with this id, or null when it's no longer offered (its list closed).
FreePack? freePackById(String id) {
  for (final p in freePacks) {
    if (p.id == id) return p;
  }
  return null;
}
