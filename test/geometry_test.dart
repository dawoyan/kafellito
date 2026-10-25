import 'package:flutter_test/flutter_test.dart';
import 'package:kafelito/geometry.dart';
import 'package:kafelito/models.dart';
import 'package:kafelito/surfaces.dart';

void main() {
  const square = [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)];

  test('interior angles of a square are 90 in both orientations', () {
    for (var i = 0; i < 4; i++) {
      expect(interiorAngle(square, i), closeTo(90, 1e-9));
      expect(interiorAngle(square.reversed.toList(), i), closeTo(90, 1e-9));
    }
  });

  test('reflex corner of an L shape is 270', () {
    const l = [Offset(0, 0), Offset(200, 0), Offset(200, 100), Offset(100, 100), Offset(100, 200), Offset(0, 200)];
    expect(interiorAngle(l, 3), closeTo(270, 1e-9));
    expect(interiorAngle(l, 0), closeTo(90, 1e-9));
  });

  test('setting an angle keeps the previous wall and the next wall length', () {
    for (var i = 0; i < 4; i++) {
      final out = setVertexAngle(square, i, 80);
      expect(interiorAngle(out, i), closeTo(80, 1e-6));
      final n = out.length;
      expect(out[(i - 1 + n) % n], square[(i - 1 + n) % n]);
      expect((out[(i + 1) % n] - out[i]).distance, closeTo(100, 1e-6));
    }
  });

  test('setting a wall length', () {
    final out = setEdgeLength(square, 1, 150);
    expect((out[2] - out[1]).distance, closeTo(150, 1e-9));
    expect((out[1] - out[0]).distance, closeTo(100, 1e-9));
  });

  test('inward normal points inside', () {
    final n = inwardNormal(square, 0);
    expect(n.dy, closeTo(1, 1e-9));
  });

  test('tile count on a 100x100 floor with 30x30 tiles', () {
    final tile = Tile(widthCm: 30, heightCm: 30);
    final p = Project(points: List.of(square), closed: true, groutMm: 0)..floor.tileId = tile.id;
    final c = countTiles(p, {tile.id: tile})[tile.id]!;
    expect(c.full, 9);
    expect(c.cut, 7);
    expect(c.areaCm2 / 10000, closeTo(1.0, 0.03));
  });

  test('door is not tiled', () {
    final tile = Tile(widthCm: 10, heightCm: 10);
    final p = Project(points: List.of(square), closed: true, groutMm: 0);
    p.walls[0].height = 200;
    p.walls[0].tiling.tileId = tile.id;
    p.walls[0].openings.add(Opening(x: 10, width: 80, height: 200));
    final c = countTiles(p, {tile.id: tile})[tile.id]!;
    expect(c.areaCm2, closeTo(100 * 200 - 80 * 200, 50));
  });

  test('json round trip', () {
    final p = Project(points: List.of(square), closed: true);
    p.fixtures.add(Fixture(type: FixtureType.sink, pos: const Offset(50, 23)));
    final q = Project.fromJson(decodeJson(jsonOf(p)));
    expect(q.points, p.points);
    expect(q.walls.length, 4);
    expect(q.fixtures.single.type, FixtureType.sink);
  });
}
