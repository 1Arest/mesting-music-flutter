/// Stable public IDs are shared by preferences, track choices and download
/// tasks. These are LX resolvers for NetEase IDs, not additional user accounts.
enum LxMusicSource {
  changqing('长青'),
  fish('Fish'),
  helloworld('HelloWorld'),
  huanyin('幻音'),
  huibq('Huibq'),
  hyw('HYW'),
  jiexiang('杰翔'),
  lx('LX'),
  qdy('全豆要'),
  xinghai('星海'),
  yuningxi('玉宁熙');

  const LxMusicSource(this.title);
  final String title;
  String get label => '$title · $name';
  String get adapter => 'LX · $name';
  String get asset => 'third_party/lx_music_source/scripts/$name.js';
}
