import 'package:flutter/material.dart';

import '../store.dart';
import '../surfaces.dart';

/// Paint that fills with the repeating tile texture. The canvas is expected to
/// be in surface centimetres. Walls have y pointing up, so their texture is
/// flipped to keep photos upright; [flipX] undoes a canvas mirrored in x.
Paint? tilePaint(AppStore store, String key, Offset origin, {bool flipY = false, bool flipX = false}) {
  final tex = store.texture(key);
  if (tex == null) {
    final t = store.tileOfKey(key);
    return t == null ? null : (Paint()..color = t.color);
  }
  final m = Matrix4.identity()
    ..translateByDouble(origin.dx, origin.dy, 0, 1)
    ..scaleByDouble((flipX ? -1 : 1) / tex.ppc, (flipY ? -1 : 1) / tex.ppc, 1, 1);
  return Paint()
    ..shader = ImageShader(tex.image, TileMode.repeated, TileMode.repeated, m.storage)
    ..filterQuality = FilterQuality.medium;
}

/// Paints a surface's tiling: base, regions, then holes on top.
void paintSurface(
  Canvas c,
  AppStore store,
  SurfaceModel s, {
  required Color plain,
  bool flipY = false,
  bool flipX = false,
  Color holeColor = Colors.white,
}) {
  final basePath = Path()..addPolygon(s.base, true);
  c.save();
  c.clipPath(basePath);
  final bp = s.tiling.tileId == null ? null : tilePaint(store, s.keyOfLayer(-1), s.origin, flipY: flipY, flipX: flipX);
  c.drawPath(basePath, bp ?? (Paint()..color = plain));
  for (var i = 0; i < s.tiling.regions.length; i++) {
    final r = s.tiling.regions[i];
    if (r.points.length < 3) continue;
    final p = tilePaint(store, s.keyOfLayer(i), s.origin, flipY: flipY, flipX: flipX);
    if (p != null) c.drawPath(Path()..addPolygon(r.points, true), p);
  }
  for (final h in s.holes) {
    c.drawRect(h, Paint()..color = holeColor);
  }
  c.restore();
}
