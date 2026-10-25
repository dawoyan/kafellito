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
    expect(c.full + c.cut, 5 * 8);
    expect(c.cut, greaterThan(0));
    final total = countTiles(p, tiles)[t.id]!;
    expect(total.pieces, c.full + c.cut);
    final j = Project.fromJson(p.toJson());
    expect(j.walls[0].tiling.rotated, true);
    expect(j.walls[0].tiling.gapMm, 5);
  });
}
