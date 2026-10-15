/// Free public channel packs (same list as Black Mango 1.x).
class FreePack {
  final String id;
  final String name;
  final String desc;
  final String url;
  final String icon;
  const FreePack(this.id, this.name, this.desc, this.url, this.icon);
}

const freePacks = [
  FreePack('iptv-org-all', 'IPTV-Org (All)', '8000+ channels, 100+ countries. Updated daily by bot.',
      'https://iptv-org.github.io/iptv/index.m3u', '📡'),
  FreePack('iptv-org-us', 'IPTV-Org US Only', 'US channels only from iptv-org.',
      'https://iptv-org.github.io/iptv/countries/us.m3u', '🇺🇸'),
  FreePack('iptv-org-news', 'IPTV-Org News', 'News channels worldwide.',
      'https://iptv-org.github.io/iptv/categories/news.m3u', '📰'),
  FreePack('iptv-org-sports', 'IPTV-Org Sports', 'Sports channels worldwide.',
      'https://iptv-org.github.io/iptv/categories/sports.m3u', '⚽'),
  FreePack('iptv-org-movies', 'IPTV-Org Movies', 'Movie channels worldwide.',
      'https://iptv-org.github.io/iptv/categories/movies.m3u', '🎬'),
  FreePack('free-tv', 'Free-TV Curated', '500+ verified free channels. No adult. HD preferred.',
      'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8', '📺'),
  FreePack('samsung', 'Samsung TV Plus', 'Samsung free US channels.', 'https://apsattv.com/ssungusa.m3u', '🖥️'),
  FreePack('roku', 'Roku Channel', '300+ channels US/EU. Most US streams are geo-blocked, VPN required.',
      'https://www.apsattv.com/rok.m3u', '📱'),
  FreePack('vizio', 'Vizio WatchFree', 'Vizio free channels.', 'https://www.apsattv.com/vizio.m3u', '📻'),
  FreePack('distro', 'DistroTV', 'DistroTV free channels.', 'https://www.apsattv.com/distro.m3u', '🌎'),
  FreePack('xumo', 'XUMO', 'XUMO free channels.', 'https://www.apsattv.com/xumo.m3u', '📲'),
  FreePack('lg', 'LG Channels', 'LG free channels.', 'https://www.apsattv.com/lg.m3u', '🖥️'),
  FreePack('tubi', 'Tubi TV', 'Tubi free movies and TV.',
      'https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists/tubi_all.m3u', '🍿'),
];
