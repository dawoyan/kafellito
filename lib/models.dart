import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

int _idCounter = 0;

String newId() {
  _idCounter++;
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = math.Random().nextInt(1 << 30).toRadixString(36);
  return '$t$r$_idCounter';
}

List<double> _pt(Offset o) => [_r(o.dx), _r(o.dy)];
Offset _off(dynamic l) => Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
double _r(double v) => (v * 100).roundToDouble() / 100;
double _d(dynamic v, double def) => v == null ? def : (v as num).toDouble();

/// A tile type in the library. Sizes are in centimetres.
class Tile {
  String id;
  String code;
  String name;
  double widthCm;
  double heightCm;
  int colorValue;
  String? imageBase64;
  int? piecesPerBox;

  Tile({
    String? id,
    this.code = '',
    this.name = '',
    this.widthCm = 30,
    this.heightCm = 30,
    this.colorValue = 0xFFD9D4C7,
    this.imageBase64,
    this.piecesPerBox,
  }) : id = id ?? newId();

  Color get color => Color(colorValue);

  String get label {
    final c = code.isEmpty ? '' : '$code · ';
    return '$c${name.isEmpty ? 'Tile' : name} (${_fmt(widthCm)}×${_fmt(heightCm)})';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'w': widthCm,
        'h': heightCm,
        'color': colorValue,
        if (imageBase64 != null) 'img': imageBase64,
        if (piecesPerBox != null) 'ppb': piecesPerBox,
      };

  factory Tile.fromJson(Map<String, dynamic> j) => Tile(
        id: j['id'] as String,
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
        widthCm: _d(j['w'], 30),
        heightCm: _d(j['h'], 30),
        colorValue: j['color'] as int? ?? 0xFFD9D4C7,
        imageBase64: j['img'] as String?,
        piecesPerBox: j['ppb'] as int?,
      );
}

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
String fmtNum(double v) => _fmt(v);

/// A polygon drawn on a surface that is covered with its own tile.
class Region {
  String id;
  List<Offset> points;
  String tileId;

  Region({String? id, required this.points, required this.tileId}) : id = id ?? newId();

  Map<String, dynamic> toJson() => {'id': id, 'pts': points.map(_pt).toList(), 'tile': tileId};

  factory Region.fromJson(Map<String, dynamic> j) => Region(
        id: j['id'] as String,
        points: (j['pts'] as List).map(_off).toList(),
        tileId: j['tile'] as String,
      );

  Region copy() => Region(id: id, points: List.of(points), tileId: tileId);
}

enum OpeningType { door, window }

/// Door or window cut out of a wall. x is from the wall start, y from the floor.
class Opening {
  String id;
  OpeningType type;
  double x;
  double y;
  double width;
  double height;

  Opening({String? id, this.type = OpeningType.door, this.x = 0, this.y = 0, this.width = 80, this.height = 205})
      : id = id ?? newId();

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type.name, 'x': x, 'y': y, 'w': width, 'h': height};

  factory Opening.fromJson(Map<String, dynamic> j) => Opening(
        id: j['id'] as String,
        type: OpeningType.values.byName(j['type'] as String? ?? 'door'),
        x: _d(j['x'], 0),
        y: _d(j['y'], 0),
        width: _d(j['w'], 80),
        height: _d(j['h'], 205),
      );
}

/// Tiling of one surface: an optional base tile plus regions with other tiles.
class SurfaceTiling {
  String? tileId;
  List<Region> regions;

  SurfaceTiling({this.tileId, List<Region>? regions}) : regions = regions ?? [];

  bool get isTiled => tileId != null || regions.isNotEmpty;

  Map<String, dynamic> toJson() => {
        if (tileId != null) 'tile': tileId,
        'regions': regions.map((r) => r.toJson()).toList(),
      };

  factory SurfaceTiling.fromJson(Map<String, dynamic>? j) => j == null
      ? SurfaceTiling()
      : SurfaceTiling(
          tileId: j['tile'] as String?,
          regions: ((j['regions'] as List?) ?? []).map((e) => Region.fromJson(e as Map<String, dynamic>)).toList(),
        );
}

/// Wall i runs from room point i to point i+1.
class Wall {
  double height;
  SurfaceTiling tiling;
  List<Opening> openings;

  Wall({this.height = 250, SurfaceTiling? tiling, List<Opening>? openings})
      : tiling = tiling ?? SurfaceTiling(),
        openings = openings ?? [];

  Map<String, dynamic> toJson() => {
        'h': height,
        'tiling': tiling.toJson(),
        'openings': openings.map((o) => o.toJson()).toList(),
      };

  factory Wall.fromJson(Map<String, dynamic> j) => Wall(
        height: _d(j['h'], 250),
        tiling: SurfaceTiling.fromJson(j['tiling'] as Map<String, dynamic>?),
        openings: ((j['openings'] as List?) ?? []).map((e) => Opening.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

enum FixtureType { sink, toilet, shower, bathtub, washer, cabinet, mirror }

class FixtureSpec {
  final String label;
  final double w, d, h;
  final double elevation;
  const FixtureSpec(this.label, this.w, this.d, this.h, [this.elevation = 0]);
}

const fixtureSpecs = {
  FixtureType.sink: FixtureSpec('Sink', 60, 46, 85),
  FixtureType.toilet: FixtureSpec('Toilet', 38, 65, 80),
  FixtureType.shower: FixtureSpec('Shower', 90, 90, 200),
  FixtureType.bathtub: FixtureSpec('Bathtub', 170, 75, 56),
  FixtureType.washer: FixtureSpec('Washing machine', 60, 60, 85),
  FixtureType.cabinet: FixtureSpec('Cabinet', 80, 40, 60, 110),
  FixtureType.mirror: FixtureSpec('Mirror', 60, 3, 80, 110),
};

/// A sink, shower etc. Position is the footprint centre in plan coordinates.
/// The back of the fixture faces -y in its local frame; rotation is radians.
class Fixture {
  String id;
  FixtureType type;
  Offset pos;
  double rotation;
  double width, depth, height, elevation;

  Fixture({
    String? id,
    required this.type,
    required this.pos,
    this.rotation = 0,
    double? width,
    double? depth,
    double? height,
    double? elevation,
  })  : id = id ?? newId(),
        width = width ?? fixtureSpecs[type]!.w,
        depth = depth ?? fixtureSpecs[type]!.d,
        height = height ?? fixtureSpecs[type]!.h,
        elevation = elevation ?? fixtureSpecs[type]!.elevation;

  String get label => fixtureSpecs[type]!.label;

  /// Converts a point in the fixture's local frame to plan coordinates.
  Offset toPlan(double lx, double ly) {
    final c = math.cos(rotation), s = math.sin(rotation);
    return pos + Offset(lx * c - ly * s, lx * s + ly * c);
  }

  Offset toLocal(Offset p) {
    final d = p - pos;
    final c = math.cos(rotation), s = math.sin(rotation);
    return Offset(d.dx * c + d.dy * s, -d.dx * s + d.dy * c);
  }

  bool contains(Offset p) {
    final l = toLocal(p);
    return l.dx.abs() <= width / 2 && l.dy.abs() <= depth / 2;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'pos': _pt(pos),
        'rot': rotation,
        'w': width,
        'd': depth,
        'h': height,
        'el': elevation,
      };

  factory Fixture.fromJson(Map<String, dynamic> j) {
    final t = FixtureType.values.byName(j['type'] as String);
    return Fixture(
      id: j['id'] as String,
      type: t,
      pos: _off(j['pos']),
      rotation: _d(j['rot'], 0),
      width: _d(j['w'], fixtureSpecs[t]!.w),
      depth: _d(j['d'], fixtureSpecs[t]!.d),
      height: _d(j['h'], fixtureSpecs[t]!.h),
      elevation: _d(j['el'], fixtureSpecs[t]!.elevation),
    );
  }
}

/// One room: plan polygon in centimetres (x right, y down on the plan).
class Project {
  String id;
  String name;
  List<Offset> points;
  bool closed;
  List<Wall> walls;
  SurfaceTiling floor;
  List<Fixture> fixtures;
  double groutMm;
  double wastePct;
  DateTime updated;

  Project({
    String? id,
    this.name = 'Bathroom',
    List<Offset>? points,
    this.closed = false,
    List<Wall>? walls,
    SurfaceTiling? floor,
    List<Fixture>? fixtures,
    this.groutMm = 2,
    this.wastePct = 10,
    DateTime? updated,
  })  : id = id ?? newId(),
        points = points ?? [],
        walls = walls ?? [],
        floor = floor ?? SurfaceTiling(),
        fixtures = fixtures ?? [],
        updated = updated ?? DateTime.now() {
    syncWalls();
  }

  int get edgeCount => closed ? points.length : math.max(0, points.length - 1);

  /// Keeps one wall entry per point.
  void syncWalls() {
    while (walls.length < points.length) {
      walls.add(Wall(height: walls.isEmpty ? 250 : walls.last.height));
    }
    while (walls.length > points.length) {
      walls.removeLast();
    }
  }

  Offset wallStart(int i) => points[i];
  Offset wallEnd(int i) => points[(i + 1) % points.length];
  double wallLength(int i) => (wallEnd(i) - wallStart(i)).distance;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pts': points.map(_pt).toList(),
        'closed': closed,
        'walls': walls.map((w) => w.toJson()).toList(),
        'floor': floor.toJson(),
        'fixtures': fixtures.map((f) => f.toJson()).toList(),
        'grout': groutMm,
        'waste': wastePct,
        'updated': updated.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Room',
        points: ((j['pts'] as List?) ?? []).map(_off).toList(),
        closed: j['closed'] as bool? ?? false,
        walls: ((j['walls'] as List?) ?? []).map((e) => Wall.fromJson(e as Map<String, dynamic>)).toList(),
        floor: SurfaceTiling.fromJson(j['floor'] as Map<String, dynamic>?),
        fixtures: ((j['fixtures'] as List?) ?? []).map((e) => Fixture.fromJson(e as Map<String, dynamic>)).toList(),
        groutMm: _d(j['grout'], 2),
        wastePct: _d(j['waste'], 10),
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
      );

  Project clone() => Project.fromJson(toJson());
}

String jsonOf(Project p) => jsonEncode(p.toJson());
Map<String, dynamic> decodeJson(String s) => jsonDecode(s) as Map<String, dynamic>;
