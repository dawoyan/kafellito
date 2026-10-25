import 'dart:math' as math;
import 'dart:ui';

import 'geometry.dart';
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

  SurfaceModel({
    required this.name,
    required this.base,
    required this.tiling,
    this.holes = const [],
    this.origin = Offset.zero,
    this.wallIndex,
  });

  bool get isFloor => wallIndex == null;

  /// Tile id at [p], [plainKey] for untiled surface, or null outside or in a hole.
  String? classify(Offset p) {
    if (!pointInPolygon(p, base)) return null;
    for (final h in holes) {
      if (h.contains(p)) return null;
    }
    for (var i = tiling.regions.length - 1; i >= 0; i--) {
      final r = tiling.regions[i];
      if (r.points.length >= 3 && pointInPolygon(p, r.points)) return r.tileId;
    }
    return tiling.tileId ?? plainKey;
  }

  Rect get bounds => boundsOf(base);

  static SurfaceModel floor(Project p) => SurfaceModel(
        name: 'Floor',
        base: p.points,
        tiling: p.floor,
        origin: p.points.isEmpty ? Offset.zero : boundsOf(p.points).topLeft,
      );

  static SurfaceModel wall(Project p, int i) {
    final w = p.walls[i];
    final len = p.wallLength(i);
    return SurfaceModel(
      name: 'Wall ${i + 1}',
      base: [Offset.zero, Offset(len, 0), Offset(len, w.height), Offset(0, w.height)],
      tiling: w.tiling,
      holes: w.openings.map((o) => o.rect).toList(),
      wallIndex: i,
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
  int? boxes(double pct) =>
      tile.piecesPerBox == null || tile.piecesPerBox! <= 0 ? null : (withWaste(pct) / tile.piecesPerBox!).ceil();
}

/// Counts the tiles needed for every tile type used in the project. A tile
/// that is only partly inside its area counts as one cut tile.
Map<String, TileCount> countTiles(Project project, Map<String, Tile> tiles) {
  final result = <String, TileCount>{};
  final grout = project.groutMm / 10;
  for (final s in SurfaceModel.all(project)) {
    final used = <String>{
      if (s.tiling.tileId != null) s.tiling.tileId!,
      ...s.tiling.regions.map((r) => r.tileId),
    };
    for (final id in used) {
      final tile = tiles[id];
      if (tile == null || tile.widthCm <= 0 || tile.heightCm <= 0) continue;
      final tc = result.putIfAbsent(id, () => TileCount(tile));
      tc.areaCm2 += _areaOf(s, id);
      final pw = tile.widthCm + grout, ph = tile.heightCm + grout;
      final b = s.bounds;
      final i0 = ((b.left - s.origin.dx) / pw).floor(), i1 = ((b.right - s.origin.dx) / pw).ceil();
      final j0 = ((b.top - s.origin.dy) / ph).floor(), j1 = ((b.bottom - s.origin.dy) / ph).ceil();
      final cells = math.max(1, (i1 - i0) * (j1 - j0));
      final n = math.sqrt(300000 / cells).floor().clamp(3, 10);
      var pieces = 0;
      for (var i = i0; i < i1; i++) {
        for (var j = j0; j < j1; j++) {
          final x0 = s.origin.dx + i * pw, y0 = s.origin.dy + j * ph;
          var hit = 0;
          for (var a = 0; a < n; a++) {
            for (var c = 0; c < n; c++) {
              final p = Offset(x0 + (a + 0.5) / n * tile.widthCm, y0 + (c + 0.5) / n * tile.heightCm);
              if (s.classify(p) == id) hit++;
            }
          }
          if (hit == 0) continue;
          final f = hit / (n * n);
          if (f > 0.97) {
            tc.full++;
          } else {
            tc.cut++;
          }
          pieces++;
        }
      }
      tc.perSurface[s.name] = (tc.perSurface[s.name] ?? 0) + pieces;
    }
  }
  return result;
}

/// Area of [s] covered by [key], sampled on a fine grid.
double _areaOf(SurfaceModel s, String key) {
  final b = s.bounds;
  final step = math.max(1.0, math.sqrt(b.width * b.height / 200000));
  var hits = 0;
  for (var x = b.left + step / 2; x < b.right; x += step) {
    for (var y = b.top + step / 2; y < b.bottom; y += step) {
      if (s.classify(Offset(x, y)) == key) hits++;
    }
  }
  return hits * step * step;
}
