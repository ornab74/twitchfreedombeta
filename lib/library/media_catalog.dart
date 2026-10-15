import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../security/vault.dart';

enum LibraryKind { music, stream, tvShow, movie }

@immutable
class LibraryEntry {
  const LibraryEntry({required this.id, required this.kind, required this.title,
    required this.source, this.description = '', this.artwork = '',
    this.artist = '', this.year, this.generatedDescription = false});
  final String id;
  final LibraryKind kind;
  final String title, source, description, artwork, artist;
  final int? year;
  final bool generatedDescription;

  Map<String, Object?> toJson() => {
    'id': id, 'kind': kind.name, 'title': title, 'source': source,
    'description': description, 'artwork': artwork, 'artist': artist,
    'year': year, 'generatedDescription': generatedDescription,
  };
  factory LibraryEntry.fromJson(Map<String, Object?> j) => LibraryEntry(
    id: j['id'] as String? ?? '',
    kind: LibraryKind.values.firstWhere((k) => k.name == j['kind'],
      orElse: () => LibraryKind.movie),
    title: j['title'] as String? ?? '',
    source: j['source'] as String? ?? '',
    description: j['description'] as String? ?? '',
    artwork: j['artwork'] as String? ?? '',
    artist: j['artist'] as String? ?? '',
    year: j['year'] as int?,
    generatedDescription: j['generatedDescription'] == true,
  );
  LibraryEntry copyWith({String? description, String? artwork,
    bool? generatedDescription}) => LibraryEntry(
      id:id, kind:kind, title:title, source:source, artist:artist, year:year,
      description:description ?? this.description,
      artwork:artwork ?? this.artwork,
      generatedDescription:generatedDescription ?? this.generatedDescription);
}

/// Catalog rows and custom metadata live inside the user's encrypted vault.
/// Library paths are metadata only: raw media is never uploaded or copied.
final class MediaCatalog extends ChangeNotifier {
  MediaCatalog(this.vault);
  final VaultRepository vault;
  final Map<String, LibraryEntry> _entries = {};
  bool _loaded = false;
  bool get loaded => _loaded;
  List<LibraryEntry> list(LibraryKind kind, {String query = ''}) {
    final needle = query.trim().toLowerCase();
    final results = _entries.values.where((e) => e.kind == kind &&
      (needle.isEmpty || e.title.toLowerCase().contains(needle) ||
       e.artist.toLowerCase().contains(needle))).toList();
    results.sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return results;
  }
  Future<void> load() async {
    _entries.clear();
    for (final json in await vault.getAllJson('media_catalog')) {
      final e = LibraryEntry.fromJson(json);
      if (e.id.isNotEmpty) _entries[e.id] = e;
    }
    _loaded = true;
    notifyListeners();
  }
  Future<void> upsert(LibraryEntry item) async {
    if (item.id.isEmpty || item.title.trim().isEmpty) {
      throw ArgumentError('Item needs an ID and title.');
    }
    await vault.putJson('media_catalog', item.id, item.toJson());
    _entries[item.id] = item;
    notifyListeners();
  }
  Future<void> remove(String id) async {
    await vault.delete('media_catalog', id);
    _entries.remove(id);
    notifyListeners();
  }

  /// Explicit user-requested directory scan; never follows symlink directories.
  /// Limits item count and skips filesystem metadata that isn't a media file.
  /// Finds artwork next to the media, avoiding network requests and trackers.
  /// Returns null when no predictable, existing sidecar artwork is present.
  Future<String?> discoverArtwork(LibraryEntry entry) async {
    if (entry.kind == LibraryKind.stream) return null;
    final media = File(entry.source);
    final directory = media.parent.path;
    final stem = p.basenameWithoutExtension(entry.source);
    for (final filename in <String>[
      '$stem.jpg', '$stem.png', '$stem.webp',
      'poster.jpg', 'poster.png', 'folder.jpg', 'cover.jpg',
    ]) {
      final candidate = File(p.join(directory, filename));
      if (await candidate.exists()) {
        final stat = await candidate.stat();
        if (stat.type == FileSystemEntityType.file && stat.size <= 15 * 1024 * 1024) {
          return candidate.path;
        }
      }
    }
    return null;
  }

  Future<int> importDirectory(String root, LibraryKind kind,
      {int limit = 10000}) async {
    if (kind == LibraryKind.stream) {
      throw ArgumentError('Live streams are added by channel, not file scan.');
    }
    final dir = Directory(root);
    if (!await dir.exists()) throw FileSystemException('Folder missing', root);
    final extensions = switch(kind) {
      LibraryKind.music => {'.mp3','.flac','.m4a','.ogg','.opus','.wav'},
      _ => {'.mkv','.mp4','.mov','.avi','.webm','.m4v'},
    };
    var count = 0;
    await for (final file in dir.list(recursive:true,followLinks:false)) {
      if (file is! File || !extensions.contains(p.extension(file.path).toLowerCase())) continue;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      final id = '${kind.name}:${p.normalize(file.absolute.path)}';
      if (!_entries.containsKey(id)) {
        await upsert(LibraryEntry(id:id,kind:kind,
          title:p.basenameWithoutExtension(file.path).replaceAll('_',' '),
          source:file.absolute.path,
          artwork: await discoverArtwork(LibraryEntry(id:id,kind:kind,
            title:p.basenameWithoutExtension(file.path),source:file.absolute.path)) ?? ''));
        count++;
      }
      if (count >= limit) break;
    }
    return count;
  }
}
