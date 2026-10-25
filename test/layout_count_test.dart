import 'package:flutter_test/flutter_test.dart';
import 'package:kafelito/models.dart';
import 'package:kafelito/surfaces.dart';

void main() {
  test('gap and rotation change the wall tile count', () {
    final t = Tile(widthCm: 30, heightCm: 60);
    final p = Project(
      points: const [Offset(0, 0), Offset(300, 0), Offset(300, 200), Offset(0, 200)],
      closed: true,
      groutMm: 0,
    );
    for (final w in p.walls) {
      w.height = 240;
    }
    p.walls[0].tiling.tileId = t.id;
    final tiles = {t.id: t};
    final s = SurfaceModel.wall(p, 0);
    final a = countLayer(s, -1, tiles)!;
    expect(a.full + a.cut, 10 * 4); // 300/30 x 240/60
    p.walls[0].tiling.rotated = true;
    final b = countLayer(SurfaceModel.wall(p, 0), -1, tiles)!;
    expect(b.full + b.cut, 5 * 8); // 300/60 x 240/30
    p.walls[0].tiling.gapMm = 5;
    final c = countLayer(SurfaceModel.wall(p, 0), -1, tiles)!;
    expect(c.full + c.cut, 6 * 8); // centred: 29 | 4 x 60 | 29 across
    expect(c.cut, greaterThan(0));
    final total = countTiles(p, tiles)[t.id]!;
    expect(total.pieces, c.full + c.cut);
    final j = Project.fromJson(p.toJson());
    expect(j.walls[0].tiling.rotated, true);
    expect(j.walls[0].tiling.gapMm, 5);
  });

  test('walls read from inside whichever way the room was drawn', () {
    const pts = [Offset(0, 0), Offset(300, 0), Offset(300, 200), Offset(0, 200)];
    final cw = Project(points: pts, closed: true);
    final ccw = Project(points: pts.reversed.toList(), closed: true);
    for (var i = 0; i < 4; i++) {
      expect(wallMirrored(cw, i), false);
      expect(wallMirrored(ccw, i), true);
    }
  });

  test('centred wall: whole tiles from the floor, equal cuts at both ends', () {
    final t = Tile(widthCm: 30, heightCm: 60);
    final p = Project(points: const [Offset(0, 0), Offset(250, 0), Offset(250, 200), Offset(0, 200)], closed: true, groutMm: 0);
    p.walls[0]
      ..height = 250
      ..tiling.tileId = t.id;
    final s = SurfaceModel.wall(p, 0);
    final cells = layoutCells(s, s.layout(-1, {t.id: t})!);
    final bottom = cells.where((c) => c.row == 0).toList();
    // 250 = 20 + 7×30 + 20.
    expect(bottom.length, 9);
    expect(bottom.first.piece.width, closeTo(20, 0.1));
    expect(bottom.last.piece.width, closeTo(20, 0.1));
    expect(bottom.every((c) => c.piece.height > 59.9), true);
    // Top row is cut: 250 = 4×60 + 10.
    expect(cells.where((c) => c.row == 4).every((c) => (c.piece.height - 10).abs() < 0.1), true);
    p.walls[0].tiling.align = TileAlign.left;
    final left = layoutCells(SurfaceModel.wall(p, 0), SurfaceModel.wall(p, 0).layout(-1, {t.id: t})!);
    expect(left.first.whole, true);
    expect(left.where((c) => c.row == 0).last.piece.width, closeTo(10, 0.1));
  });

  test('collection lays walls, floor and a decor band; try-out reverts', () {
    final wall = Tile(widthCm: 30, heightCm: 60), floor = Tile(widthCm: 60, heightCm: 60);
    final decor = Tile(widthCm: 10, heightCm: 30);
    final tiles = {for (final t in [wall, floor, decor]) t.id: t};
    final p = Project(points: const [Offset(0, 0), Offset(300, 0), Offset(300, 200), Offset(0, 200)], closed: true);
    final c = TileCollection(wallTileId: wall.id, floorTileId: floor.id, decorTileId: decor.id);
    applyCollection(p, c, tiles);
    expect(p.floor.tileId, floor.id);
    expect(p.walls.every((w) => w.tiling.tileId == wall.id), true);
    final band = p.walls[0].tiling.regions.single;
    expect(band.decor && band.rotated, true);
    expect(band.points.first.dy, closeTo(2 * 60.2, 0.01)); // on a wall-tile joint near 120 cm
    applyCollection(p, c, tiles);
    expect(p.walls[0].tiling.regions.length, 1);

    p.trialBase = jsonOf(p);
    replaceTile(p, floor.id, wall.id);
    expect(p.floor.tileId, wall.id);
    final reverted = Project.fromJson(decodeJson(p.trialBase!));
    expect(reverted.floor.tileId, floor.id);
    expect(reverted.trialBase, isNull);
  });
}
