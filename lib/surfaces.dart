import 'dart:math' as math;
import 'dart:ui';

import 'geometry.dart';
import 'i18n.dart';
import 'models.dart';

/// Marks a point that is part of a surface but has no tile.
const plainKey = '';

/// A flat surface (floor or one wall) in its own 2D coordinates, in cm.
/// Walls use x along the wall from its start and y up from the floor.
/// The floor uses plan coordinates.
class SurfaceModel {
  final String name;
  final List<Offset> base;
  final SurfaceTiling tiling;
  final List<Rect> holes;
  final Offset origin;
  final int? wallIndex;

  /// The room's tile gap, used where the tiling sets none.
  final double defaultGapMm;

  SurfaceModel({
    required this.name,
    required this.base,
    required this.tiling,
    this.holes = const [],
    this.origin = Offset.zero,
    this.wallIndex,
    this.defaultGapMm = 2,
  });

  bool get isFloor => wallIndex == null;

  /// The same surface with a different tiling, for previews.
  SurfaceModel withTiling(SurfaceTiling t) => SurfaceModel(
    name: name,
    base: base,
    tiling: t,
    holes: holes,
    origin: origin,
    wallIndex: wallIndex,
    defaultGapMm: defaultGapMm,
  );

  /// Layer at [p]: -1 for the base, a region index, or null outside or in a hole.
  int? layerAt(Offset p) {
    if (!pointInPolygon(p, base)) return null;
    for (final h in holes) {
      if (h.contains(p)) return null;
    }
    for (var i = tiling.regions.length - 1; i >= 0; i--) {
      final r = tiling.regions[i];
      if (r.points.length >= 3 && pointInPolygon(p, r.points)) return i;
    }
    return -1;
  }

  /// Layout key of a layer, or [plainKey] for an untiled base.
  String keyOfLayer(int layer) {
    if (layer < 0) {
      final t = tiling.tileId;
      return t == null ? plainKey : layoutKey(t, tiling.gapMm ?? defaultGapMm, tiling.rotated);
    }
    final r = tiling.regions[layer];
    return layoutKey(r.tileId, r.gapMm ?? defaultGapMm, r.rotated);
  }

  /// Layout key at [p], [plainKey] for untiled surface, or null outside or in a hole.
  String? classify(Offset p) {
    final l = layerAt(p);
    return l == null ? null : keyOfLayer(l);
  }

  Rect get bounds => boundsOf(base);

  static SurfaceModel floor(Project p) => SurfaceModel(
    name: tr('Floor'),
    base: p.points,
    tiling: p.floor,
    origin: p.points.isEmpty ? Offset.zero : boundsOf(p.points).topLeft,
    defaultGapMm: p.groutMm,
  );

  static SurfaceModel wall(Project p, int i) {
    final w = p.walls[i];
    final len = p.wallLength(i);
    return SurfaceModel(
      name: tr('Wall {n}', {'n': i + 1}),
      base: [Offset.zero, Offset(len, 0), Offset(len, w.height), Offset(0, w.height)],
      tiling: w.tiling,
      holes: w.openings.map((o) => o.rect).toList(),
      wallIndex: i,
      defaultGapMm: p.groutMm,
    );
  }

  static List<SurfaceModel> all(Project p) => [
    if (p.closed && p.points.length >= 3) floor(p),
    for (var i = 0; i < p.edgeCount; i++) wall(p, i),
  ];
}

class TileCount {
  final Tile tile;
  double areaCm2 = 0;
  int full = 0;
  int cut = 0;
  final Map<String, int> perSurface = {};
  TileCount(this.tile);

  int get pieces => full + cut;
  int withWaste(double pct) => (pieces * (1 + pct / 100)).ceil();
  int? boxes(double pct) => boxesFor(tile, withWaste(pct));
}

int? boxesFor(Tile tile, int pieces) =>
    tile.piecesPerBox == null || tile.piecesPerBox! <= 0 ? null : (pieces / tile.piecesPerBox!).ceil();

/// Tiles needed to cover the part of [s] where [inside] holds, laid from the
/// surface origin. A tile that is only partly inside counts as one cut tile.
({int full, int cut, double areaCm2}) countCells(
  SurfaceModel s,
  Tile tile,
  double gapMm,
  bool rotated,
  bool Function(Offset) inside,
) {
  final tw = rotated ? tile.heightCm : tile.widthCm, th = rotated ? tile.widthCm : tile.heightCm;
  if (tw <= 0 || th <= 0) return (full: 0, cut: 0, areaCm2: 0.0);
  final grout = gapMm / 10;
  final pw = tw + grout, ph = th + grout;
  final b = s.bounds;
  final i0 = ((b.left - s.origin.dx) / pw).floor(), i1 = ((b.right - s.origin.dx) / pw).ceil();
  final j0 = ((b.top - s.origin.dy) / ph).floor(), j1 = ((b.bottom - s.origin.dy) / ph).ceil();
  final cells = math.max(1, (i1 - i0) * (j1 - j0));
  final n = math.sqrt(300000 / cells).floor().clamp(3, 10);
  var full = 0, cut = 0;
  for (var i = i0; i < i1; i++) {
    for (var j = j0; j < j1; j++) {
      final x0 = s.origin.dx + i * pw, y0 = s.origin.dy + j * ph;
      var hit = 0;
      for (var a = 0; a < n; a++) {
        for (var c = 0; c < n; c++) {
          if (inside(Offset(x0 + (a + 0.5) / n * tw, y0 + (c + 0.5) / n * th))) hit++;
        }
      }
      if (hit == 0) continue;
      if (hit / (n * n) > 0.97) {
        full++;
      } else {
        cut++;
      }
    }
  }
  return (full: full, cut: cut, areaCm2: _areaOf(s, inside));
}

/// Tiles for one layer of [s] (-1 for the base), as the tile dialogs preview it.
({int full, int cut, double areaCm2})? countLayer(SurfaceModel s, int layer, Map<String, Tile> tiles) {
  if (layer >= s.tiling.regions.length) return null;
  final key = s.keyOfLayer(layer);
  final tile = tiles[tileIdOfKey(key)];
  if (key == plainKey || tile == null) return null;
  final l = layoutOfKey(key);
  return countCells(s, tile, l.gapMm, l.rotated, (p) => s.layerAt(p) == layer);
}

/// Counts the tiles needed for every tile type used in the project. Layers
/// with the same tile, gap and direction on one surface are counted together.
Map<String, TileCount> countTiles(Project project, Map<String, Tile> tiles) {
  final result = <String, TileCount>{};
  for (final s in SurfaceModel.all(project)) {
    final used = <String>{
      if (s.tiling.tileId != null) s.keyOfLayer(-1),
      for (var i = 0; i < s.tiling.regions.length; i++) s.keyOfLayer(i),
    };
    for (final key in used) {
      final id = tileIdOfKey(key);
      final tile = tiles[id];
      if (tile == null || tile.widthCm <= 0 || tile.heightCm <= 0) continue;
      final l = layoutOfKey(key);
      final c = countCells(s, tile, l.gapMm, l.rotated, (p) => s.classify(p) == key);
      final tc = result.putIfAbsent(id, () => TileCount(tile));
      tc.areaCm2 += c.areaCm2;
      tc.full += c.full;
      tc.cut += c.cut;
      tc.perSurface[s.name] = (tc.perSurface[s.name] ?? 0) + c.full + c.cut;
    }
  }
  return result;
}

double floorAreaM2(Project p) => p.closed && p.points.length >= 3 ? polygonArea(p.points) / 10000 : 0;

double wallAreaM2(Project p) {
  var a = 0.0;
  for (var i = 0; i < p.edgeCount; i++) {
    a += p.wallLength(i) * p.walls[i].height;
    for (final o in p.walls[i].openings) {
      a -= o.width * o.height;
    }
  }
  return a / 10000;
}

/// Area of [s] where [inside] holds, sampled on a fine grid.
double _areaOf(SurfaceModel s, bool Function(Offset) inside) {
  final b = s.bounds;
  final step = math.max(1.0, math.sqrt(b.width * b.height / 200000));
  var hits = 0;
  for (var x = b.left + step / 2; x < b.right; x += step) {
    for (var y = b.top + step / 2; y < b.bottom; y += step) {
      if (inside(Offset(x, y))) hits++;
    }
  }
  return hits * step * step;
}
