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

  /// True when a wall seen from inside the room runs from its end (left) to
  /// its start (right), so views must flip x to show it from inside.
  final bool mirrored;

  SurfaceModel({
    required this.name,
    required this.base,
    required this.tiling,
    this.holes = const [],
    this.origin = Offset.zero,
    this.wallIndex,
    this.defaultGapMm = 2,
    this.mirrored = false,
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
    mirrored: mirrored,
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

  /// Outline of a layer: the whole surface for the base (-1), else the region.
  List<Offset> polygonOf(int layer) => layer < 0 ? base : tiling.regions[layer].points;

  /// How the tiles of [layer] are laid, or null when it has no known tile.
  LayerLayout? layout(int layer, Map<String, Tile> tiles) {
    if (layer >= tiling.regions.length) return null;
    final key = keyOfLayer(layer);
    final tile = tiles[tileIdOfKey(key)];
    if (key == plainKey || tile == null || tile.widthCm <= 0 || tile.heightCm <= 0) return null;
    final l = layoutOfKey(key);
    final align = layer < 0 ? tiling.align : tiling.regions[layer].align;
    final tw = l.rotated ? tile.heightCm : tile.widthCm, th = l.rotated ? tile.widthCm : tile.heightCm;
    final g = l.gapMm / 10;
    final b = boundsOf(polygonOf(layer));
    // Mirrored walls have their inside-left corner at the larger x.
    final flip = mirrored;
    final double ox = switch (align) {
      TileAlign.center => _centred(b.left, b.width, tw, g),
      TileAlign.left => flip ? b.right - tw : b.left,
      TileAlign.right => flip ? b.left : b.right - tw,
    };
    // Walls start with whole tiles on the floor (lowest y); floors from the top
    // of the plan, or centred too when the layout is centred.
    final oy = !isFloor || align != TileAlign.center ? b.top : _centred(b.top, b.height, th, g);
    return LayerLayout(layer, key, tile, tw, th, g, Offset(ox, oy), align, flip);
  }

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
      mirrored: wallMirrored(p, i),
    );
  }

  static List<SurfaceModel> all(Project p) => [
    if (p.closed && p.points.length >= 3) floor(p),
    for (var i = 0; i < p.edgeCount; i++) wall(p, i),
  ];
}

/// Whether wall [i] runs right to left when seen from inside the room.
bool wallMirrored(Project p, int i) {
  if (!p.closed || p.points.length < 3 || p.wallLength(i) == 0) return false;
  final dir = p.wallEnd(i) - p.wallStart(i);
  final n = inwardNormal(p.points, i);
  // Facing the wall from inside means looking along -n; on the y-down plan
  // the viewer's right is then (n.dy, -n.dx).
  return dir.dx * n.dy - dir.dy * n.dx < 0;
}

/// Start of the first whole tile when [length] is tiled symmetrically: equal
/// cut pieces at both ends, whole tiles between. Pieces under a third of a
/// tile are avoided by dropping one whole tile, which makes them about half
/// a tile larger.
double _centred(double start, double length, double tile, double gap) {
  final pitch = tile + gap;
  var whole = ((length + gap) / pitch).floor();
  var piece = (length - (whole * pitch - gap)) / 2;
  if (piece < 0.05) return start;
  if (piece < tile / 3 && whole > 0) {
    whole -= 1;
    piece += pitch / 2;
  }
  return start + piece;
}

/// Resolved tiling of one layer of a surface: tile size as laid (after
/// rotation), gap in cm, and the corner of one whole tile in the grid.
class LayerLayout {
  final int layer;
  final String key;
  final Tile tile;
  final double tw, th, gap;
  final Offset origin;
  final TileAlign align;

  /// True when x runs right to left as seen from inside (mirrored walls).
  final bool flipX;
  const LayerLayout(this.layer, this.key, this.tile, this.tw, this.th, this.gap, this.origin, this.align, this.flipX);

  double get pw => tw + gap;
  double get ph => th + gap;
}

/// One tile position of a layout. [piece] is the part that is laid (the whole
/// [rect] for a whole tile); [row] counts up from the layout start and [col]
/// across from its start side.
class TileCell {
  final Rect rect;
  final Rect piece;
  final double fraction;
  final int row, col;

  /// Middle of the laid part, for labels; differs from [piece]'s centre on
  /// L-shaped cuts.
  final Offset center;
  const TileCell(this.rect, this.piece, this.fraction, this.row, this.col, this.center);

  bool get whole => fraction > 0.97;
}

/// Every tile of [l] on [s] that covers part of the layer, ordered from the
/// layout start: walls from the floor up, floors from the top; each row from
/// the inside-left corner (or right, when tiling starts on the right).
List<TileCell> layoutCells(SurfaceModel s, LayerLayout l, {int maxSamples = 300000, int fine = 0}) {
  bool inside(Offset p) => s.layerAt(p) == l.layer;
  final b = boundsOf(s.polygonOf(l.layer));
  final i0 = ((b.left - l.origin.dx) / l.pw).floor(), i1 = ((b.right - l.origin.dx) / l.pw).ceil();
  final j0 = ((b.top - l.origin.dy) / l.ph).floor(), j1 = ((b.bottom - l.origin.dy) / l.ph).ceil();
  final cells = math.max(1, (i1 - i0) * (j1 - j0));
  final n = fine > 0 ? fine : math.sqrt(maxSamples / cells).floor().clamp(3, 10);
  final poly = s.polygonOf(l.layer);
  final rightToLeft = l.flipX != (l.align == TileAlign.right);
  final out = <TileCell>[];
  for (var i = i0; i < i1; i++) {
    for (var j = j0; j < j1; j++) {
      final r = Rect.fromLTWH(l.origin.dx + i * l.pw, l.origin.dy + j * l.ph, l.tw, l.th);
      var hit = 0;
      var sum = Offset.zero;
      var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
      for (var a = 0; a < n; a++) {
        for (var c = 0; c < n; c++) {
          final p = Offset(r.left + (a + 0.5) / n * r.width, r.top + (c + 0.5) / n * r.height);
          if (!inside(p)) continue;
          hit++;
          sum += p;
          minX = math.min(minX, p.dx);
          maxX = math.max(maxX, p.dx);
          minY = math.min(minY, p.dy);
          maxY = math.max(maxY, p.dy);
        }
      }
      if (hit == 0) continue;
      final f = hit / (n * n);
      var piece = r;
      if (f <= 0.97) {
        // The true edge lies within one sample step outside the hits; the
        // clipped outline then gives exact edges where the layer border
        // crosses the tile. Edges of holes stay within one step.
        final hx = r.width / n, hy = r.height / n;
        piece = Rect.fromLTRB(minX - hx, minY - hy, maxX + hx, maxY + hy).intersect(r);
        final clipped = clipConvex(poly, [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
        if (clipped.length >= 3) {
          final cb = boundsOf(clipped);
          if (cb.width > 0 && cb.height > 0) piece = piece.intersect(cb.inflate(0.01));
        }
      }
      out.add(
        TileCell(r, piece, f, j - j0, rightToLeft ? i1 - 1 - i : i - i0, f > 0.97 ? r.center : sum / hit.toDouble()),
      );
    }
  }
  // Rows run up from the floor on walls (y up) and down the plan on floors.
  out.sort((a, b) => a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));
  return out;
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

/// Tiles for one layer of [s] (-1 for the base). A tile that is only partly
/// inside counts as one cut tile.
({int full, int cut, double areaCm2})? countLayer(SurfaceModel s, int layer, Map<String, Tile> tiles) {
  final l = s.layout(layer, tiles);
  if (l == null) return null;
  final cells = layoutCells(s, l);
  final full = cells.where((c) => c.whole).length;
  return (full: full, cut: cells.length - full, areaCm2: _areaOf(s, (p) => s.layerAt(p) == layer));
}

/// Counts the tiles needed for every tile type used in the project.
Map<String, TileCount> countTiles(Project project, Map<String, Tile> tiles) {
  final result = <String, TileCount>{};
  for (final s in SurfaceModel.all(project)) {
    for (var layer = -1; layer < s.tiling.regions.length; layer++) {
      final c = countLayer(s, layer, tiles);
      if (c == null) continue;
      final tile = tiles[tileIdOfKey(s.keyOfLayer(layer))]!;
      final tc = result.putIfAbsent(tile.id, () => TileCount(tile));
      tc.areaCm2 += c.areaCm2;
      tc.full += c.full;
      tc.cut += c.cut;
      tc.perSurface[s.name] = (tc.perSurface[s.name] ?? 0) + c.full + c.cut;
    }
  }
  return result;
}

/// Lays [c] in [p]: wall tile on every wall and floor tile on the floor, both
/// centred with whole tiles from the floor, plus a decor band on each wall
/// starting at the wall-tile joint nearest the collection's decor height.
/// Earlier decor bands are replaced; other drawn areas stay.
void applyCollection(Project p, TileCollection c, Map<String, Tile> tiles) {
  p.collectionId = c.id;
  if (tiles[c.floorTileId] != null) {
    p.floor
      ..tileId = c.floorTileId
      ..gapMm = null
      ..rotated = false
      ..align = TileAlign.center;
  }
  final wallTile = tiles[c.wallTileId];
  final decor = tiles[c.decorTileId];
  for (var i = 0; i < p.edgeCount; i++) {
    final w = p.walls[i];
    if (wallTile != null) {
      w.tiling
        ..tileId = wallTile.id
        ..gapMm = null
        ..rotated = false
        ..align = TileAlign.center;
    }
    w.tiling.regions.removeWhere((r) => r.decor);
    if (decor == null) continue;
    // Lay decor with its long side along the wall.
    final rotated = decor.heightCm > decor.widthCm;
    final bandH = rotated ? decor.widthCm : decor.heightCm;
    var y0 = c.decorHeightCm;
    if (wallTile != null) {
      final pitch = wallTile.heightCm + p.groutMm / 10;
      y0 = math.max(1, (c.decorHeightCm / pitch).round()) * pitch;
    }
    if (y0 + bandH > w.height) continue;
    final len = p.wallLength(i);
    w.tiling.regions.add(
      Region(
        points: [Offset(0, y0), Offset(len, y0), Offset(len, y0 + bandH), Offset(0, y0 + bandH)],
        tileId: decor.id,
        rotated: rotated,
        decor: true,
      ),
    );
  }
}

/// Puts [to] everywhere [from] is laid in [p], keeping each layout.
void replaceTile(Project p, String from, String to) {
  for (final t in [p.floor, ...p.walls.map((w) => w.tiling)]) {
    if (t.tileId == from) t.tileId = to;
    for (final r in t.regions) {
      if (r.tileId == from) r.tileId = to;
    }
  }
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
