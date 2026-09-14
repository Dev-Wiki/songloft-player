/// 歌手参与角色：主唱（artist）/ 专辑歌手（album_artist）。
class ArtistRole {
  const ArtistRole._();
  static const artist = 'artist';
  static const albumArtist = 'album_artist';
}

/// 歌手实体（GET /songs/{id}/artists 响应里的 artist 对象）。
class Artist {
  final int id;
  final String name;
  final DateTime? createdAt;

  const Artist({required this.id, required this.name, this.createdAt});

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    createdAt:
        json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
  );
}

/// 一首歌的某个参与歌手及其角色与顺序（GET 响应项）。
class SongArtist {
  final Artist artist;
  final String role; // 'artist' | 'album_artist'
  final int position;

  const SongArtist({
    required this.artist,
    required this.role,
    required this.position,
  });

  factory SongArtist.fromJson(Map<String, dynamic> json) => SongArtist(
    artist: Artist.fromJson(json['artist'] as Map<String, dynamic>),
    role: json['role'] as String? ?? ArtistRole.artist,
    position: json['position'] as int? ?? 0,
  );
}

/// 编辑歌手时的输入项（PUT /songs/{id}/artists 请求体项）。
class ArtistInput {
  final String name;
  final String role; // 'artist' | 'album_artist'，缺省 artist
  final int position;

  const ArtistInput({
    required this.name,
    this.role = ArtistRole.artist,
    this.position = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'position': position,
  };
}
