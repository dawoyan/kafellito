import 'package:flutter/material.dart';

import '../store.dart';
import '../surfaces.dart';

/// Paint that fills with the repeating tile texture. The canvas is expected to
/// be in surface centimetres. Walls have y pointing up, so their texture is
/// flipped to keep photos upright.
Paint? tilePaint(AppStore store, String tileId, double groutMm, Offset origin, {bool flipY = false}) {
  final tex = store.texture(tileId, groutMm);
  if (tex == null) {
    final t = store.tile(tileId);
    return t == null ? null : (Paint()..color = t.color);
  }
  final m = Matrix4.identity()
    ..translateByDouble(origin.dx, origin.dy, 0, 1)
    ..scaleByDouble(1 / tex.ppc, (flipY ? -1 : 1) / tex.ppc, 1, 1);
  return Paint()
    ..shader = ImageShader(tex.image, TileMode.repeated, TileMode.repeated, m.storage)
    ..filterQuality = FilterQuality.medium;
}

/// Paints a surface's tiling: base, regions, then holes on top.
void paintSurface(Canvas c, AppStore store, SurfaceModel s, double groutMm,
    {required Color plain, bool flipY = false, Color holeColor = Colors.white}) {
  final basePath = Path()..addPolygon(s.base, true);
  c.save();
  c.clipPath(basePath);
  final baseTile = s.tiling.tileId;
  final bp = baseTile == null ? null : tilePaint(store, baseTile, groutMm, s.origin, flipY: flipY);
  c.drawPath(basePath, bp ?? (Paint()..color = plain));
  for (final r in s.tiling.regions) {
    if (r.points.length < 3) continue;
    final p = tilePaint(store, r.tileId, groutMm, s.origin, flipY: flipY);
    if (p != null) c.drawPath(Path()..addPolygon(r.points, true), p);
  }
  for (final h in s.holes) {
    c.drawRect(h, Paint()..color = holeColor);
  }
  c.restore();
}
