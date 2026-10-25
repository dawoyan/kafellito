import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'i18n.dart';
import 'models.dart';
import 'storage.dart';
import 'surfaces.dart';

/// A repeating image of one tile plus its grout, used to paint surfaces.
class TileTexture {
  final ui.Image image;

  /// Image pixels per centimetre.
  final double ppc;
  TileTexture(this.image, this.ppc);
}

class AppStore extends ChangeNotifier {
  final List<Tile> tiles = [];
  final List<Project> projects = [];
  final List<TileCollection> collections = [];
  bool loaded = false;
  String lang = 'en';
  double defaultGapMm = 2;

  final Map<String, TileTexture> _textures = {};
  final Map<String, String> _textureKeys = {};
  final Map<String, Future<TileTexture>> _building = {};
  final Map<String, ui.Image> _photos = {};
  Timer? _saveTimer;

  Map<String, Tile> get tileMap => {for (final t in tiles) t.id: t};
  Tile? tile(String? id) => id == null ? null : tiles.where((t) => t.id == id).firstOrNull;

  Future<void> load() async {
    try {
      final raw = await loadData();
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        tiles.addAll(((j['tiles'] as List?) ?? []).map((e) => Tile.fromJson(e as Map<String, dynamic>)));
        projects.addAll(((j['projects'] as List?) ?? []).map((e) => Project.fromJson(e as Map<String, dynamic>)));
        collections.addAll(
          ((j['collections'] as List?) ?? []).map((e) => TileCollection.fromJson(e as Map<String, dynamic>)),
        );
        final s = j['settings'] as Map<String, dynamic>? ?? {};
        lang = s['lang'] as String? ?? 'en';
        defaultGapMm = (s['gap'] as num?)?.toDouble() ?? 2;
        appLang = lang;
      } else {
        _seed();
      }
    } catch (e) {
      debugPrint('Failed to load data: $e');
      if (tiles.isEmpty && projects.isEmpty) _seed();
    }
    loaded = true;
    notifyListeners();
  }

  void _seed() {
    final white = Tile(
      code: 'W-3060',
      name: 'Gloss white',
      widthCm: 30,
      heightCm: 60,
      colorValue: 0xFFF2F0EA,
      piecesPerBox: 8,
    );
    final blue = Tile(
      code: 'B-1010',
      name: 'Aegean blue',
      widthCm: 10,
      heightCm: 10,
      colorValue: 0xFF2F6C9E,
      piecesPerBox: 100,
    );
    final stone = Tile(
      code: 'S-6060',
      name: 'Travertine',
      widthCm: 60,
      heightCm: 60,
      colorValue: 0xFFC9B79C,
      piecesPerBox: 4,
    );
    tiles.addAll([white, blue, stone]);
    final p = Project(
      name: 'Sample bathroom',
      points: const [
        Offset(0, 0),
        Offset(240, 0),
        Offset(240, 180),
        Offset(120, 180),
        Offset(120, 260),
        Offset(0, 260),
      ],
      closed: true,
    );
    p.floor.tileId = stone.id;
    for (final w in p.walls) {
      w.tiling.tileId = white.id;
    }
    p.walls[0].tiling.regions.add(
      Region(points: const [Offset(0, 100), Offset(240, 100), Offset(240, 120), Offset(0, 120)], tileId: blue.id),
    );
    p.walls[4].openings.add(Opening(x: 20, width: 80, height: 205));
    p.fixtures.addAll([
      Fixture(type: FixtureType.sink, pos: const Offset(70, 23)),
      Fixture(type: FixtureType.toilet, pos: const Offset(160, 32.5)),
      Fixture(type: FixtureType.shower, pos: const Offset(195, 135), rotation: math.pi / 2),
      Fixture(type: FixtureType.mirror, pos: const Offset(70, 1.5)),
    ]);
    projects.add(p);
    scheduleSave();
  }

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final json = jsonEncode({
      'version': 1,
      'settings': {'lang': lang, 'gap': defaultGapMm},
      'tiles': tiles.map((t) => t.toJson()).toList(),
      'projects': projects.map((p) => p.toJson()).toList(),
      'collections': collections.map((c) => c.toJson()).toList(),
    });
    try {
      await saveData(json);
    } catch (e) {
      debugPrint('Failed to save: $e');
    }
  }

  void changed() {
    notifyListeners();
    scheduleSave();
  }

  void setLanguage(String code) {
    lang = code;
    appLang = code;
    changed();
  }

  void setDefaultGap(double mm, {bool applyToAll = false}) {
    defaultGapMm = mm;
    if (applyToAll) {
      for (final p in projects) {
        p.groutMm = mm;
      }
    }
    changed();
  }

  void upsertTile(Tile t) {
    final i = tiles.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      tiles[i] = t;
    } else {
      tiles.add(t);
    }
    _photos.remove(t.id);
    _counts.clear();
    changed();
  }

  void deleteTile(String id) {
    tiles.removeWhere((t) => t.id == id);
    _counts.clear();
    for (final p in projects) {
      _strip(p, id);
    }
    for (final c in collections) {
      if (c.wallTileId == id) c.wallTileId = null;
      if (c.floorTileId == id) c.floorTileId = null;
      if (c.decorTileId == id) c.decorTileId = null;
    }
    changed();
  }

  TileCollection? collection(String? id) => id == null ? null : collections.where((c) => c.id == id).firstOrNull;

  void upsertCollection(TileCollection c) {
    final i = collections.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      collections[i] = c;
    } else {
      collections.add(c);
    }
    changed();
  }

  void deleteCollection(String id) {
    collections.removeWhere((c) => c.id == id);
    for (final p in projects) {
      if (p.collectionId == id) p.collectionId = null;
    }
    changed();
  }

  /// Rooms that use [tileId] on a wall, the floor or a drawn area.
  List<Project> roomsUsing(String tileId) => projects.where((p) {
    bool uses(SurfaceTiling t) => t.tileId == tileId || t.regions.any((r) => r.tileId == tileId);
    return uses(p.floor) || p.walls.any((w) => uses(w.tiling));
  }).toList();

  /// Takes [tileId] off every surface of [p] and deletes its drawn areas.
  void removeTileFromRoom(Project p, String tileId) {
    _strip(p, tileId);
    upsertProject(p);
  }

  void _strip(Project p, String id) {
    for (final t in [p.floor, ...p.walls.map((w) => w.tiling)]) {
      if (t.tileId == id) {
        t
          ..tileId = null
          ..gapMm = null
          ..rotated = false;
      }
      t.regions.removeWhere((r) => r.tileId == id);
    }
  }

  void upsertProject(Project p) {
    p.updated = DateTime.now();
    final i = projects.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      projects[i] = p;
    } else {
      projects.add(p);
    }
    changed();
  }

  void deleteProject(String id) {
    projects.removeWhere((p) => p.id == id);
    changed();
  }

  /// Tile of a layout key (see [layoutKey]) or a plain tile id.
  Tile? tileOfKey(String key) => tile(tileIdOfKey(key));

  /// Returns the texture for a layout key, building it in the background when
  /// missing. Listeners are notified once it is ready.
  TileTexture? texture(String key) {
    final t = tileOfKey(key);
    if (t == null) return null;
    final l = layoutOfKey(key);
    final sig = '${t.widthCm}|${t.heightCm}|${t.colorValue}|${t.imageBase64?.length}';
    final tex = _textures[key];
    if (tex != null && _textureKeys[key] == sig) return tex;
    if (!_building.containsKey('$key$sig')) {
      _building['$key$sig'] = _buildTexture(t, l.gapMm, l.rotated).then((value) {
        _textures[key] = value;
        _textureKeys[key] = sig;
        _building.remove('$key$sig');
        notifyListeners();
        return value;
      });
    }
    return tex;
  }

  /// Like [texture], but waits for it to be built.
  Future<TileTexture?> loadTexture(String key) async {
    final tex = texture(key);
    if (tex != null) return tex;
    final t = tileOfKey(key);
    if (t == null) return null;
    final sig = '${t.widthCm}|${t.heightCm}|${t.colorValue}|${t.imageBase64?.length}';
    return await (_building['$key$sig'] ?? Future.value(_textures[key]));
  }

  final Map<String, (int, Map<String, TileCount>)> _counts = {};

  /// Tile counts for [p], cached until the room or the tile library changes.
  Map<String, TileCount> countsFor(Project p) {
    final stamp = p.updated.microsecondsSinceEpoch;
    final c = _counts[p.id];
    if (c != null && c.$1 == stamp) return c.$2;
    final r = countTiles(p, tileMap);
    _counts[p.id] = (stamp, r);
    return r;
  }

  Future<ui.Image?> photo(Tile t) async {
    if (t.imageBase64 == null) return null;
    final cached = _photos[t.id];
    if (cached != null) return cached;
    final codec = await ui.instantiateImageCodec(base64Decode(t.imageBase64!));
    final img = (await codec.getNextFrame()).image;
    _photos[t.id] = img;
    return img;
  }

  Future<TileTexture> _buildTexture(Tile t, double groutMm, bool rotated) async {
    final g = math.max(groutMm / 10, 0.0);
    final tw = rotated ? t.heightCm : t.widthCm, th = rotated ? t.widthCm : t.heightCm;
    final ppc = math.min(10.0, 256 / math.max(tw, th));
    final wpx = ((tw + g) * ppc).round().clamp(2, 1024);
    final hpx = ((th + g) * ppc).round().clamp(2, 1024);
    final realPpcX = wpx / (tw + g);
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    final gpx = g * ppc;
    c.drawRect(ui.Rect.fromLTWH(0, 0, wpx.toDouble(), hpx.toDouble()), ui.Paint()..color = const ui.Color(0xFFBDB8AE));
    final inner = ui.Rect.fromLTWH(gpx / 2, gpx / 2, wpx - gpx, hpx - gpx);
    final photo = await this.photo(t);
    if (photo != null) {
      c.save();
      var dst = inner;
      if (rotated) {
        // Turn the photo with the tile so its pattern follows the new direction.
        c.translate(inner.center.dx, inner.center.dy);
        c.rotate(math.pi / 2);
        dst = ui.Rect.fromCenter(center: ui.Offset.zero, width: inner.height, height: inner.width);
      }
      c.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
        dst,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      c.restore();
    } else {
      final base = t.color;
      c.drawRect(inner, ui.Paint()..color = base);
      // A soft highlight so plain tiles read as glazed ceramic.
      c.drawRect(
        inner,
        ui.Paint()
          ..shader = ui.Gradient.linear(
            inner.topLeft,
            inner.bottomRight,
            [const ui.Color(0x33FFFFFF), const ui.Color(0x00FFFFFF), const ui.Color(0x1A000000)],
            [0, 0.5, 1],
          ),
      );
    }
    final img = await rec.endRecording().toImage(wpx, hpx);
    return TileTexture(img, realPpcX);
  }

  /// Average colour of an encoded image, used as a tile's plan colour.
  static Future<int> averageColor(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 8, targetHeight: 8);
    final img = (await codec.getNextFrame()).image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 0xFFD9D4C7;
    var r = 0, g = 0, b = 0;
    final n = data.lengthInBytes ~/ 4;
    for (var i = 0; i < n; i++) {
      r += data.getUint8(i * 4);
      g += data.getUint8(i * 4 + 1);
      b += data.getUint8(i * 4 + 2);
    }
    return 0xFF000000 | ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
  }
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppStore read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
