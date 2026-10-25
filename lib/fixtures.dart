import 'package:flutter/material.dart';

import 'models.dart';

IconData fixtureIcon(FixtureType t) => switch (t) {
  FixtureType.sink => Icons.wash,
  FixtureType.toilet => Icons.wc,
  FixtureType.shower => Icons.shower,
  FixtureType.bathtub => Icons.bathtub,
  FixtureType.washer => Icons.local_laundry_service,
  FixtureType.cabinet => Icons.kitchen,
  FixtureType.mirror => Icons.crop_portrait,
};

/// Box in the fixture's local frame: x across, y from back (-d/2) to front,
/// z up from the floor.
class Box3 {
  final double x0, x1, y0, y1, z0, z1;
  final Color color;
  const Box3(this.x0, this.x1, this.y0, this.y1, this.z0, this.z1, this.color);
}

const _white = Color(0xFFF7F7F5);
const _chrome = Color(0xFFB8BEC4);
const _wood = Color(0xFF9C7350);
const _glass = Color(0x5594C4D8);

/// Simple placeholder 3D model of a fixture.
List<Box3> fixtureBoxes(Fixture f) {
  final w = f.width / 2, d = f.depth / 2, h = f.height, e = f.elevation;
  switch (f.type) {
    case FixtureType.sink:
      return [
        Box3(-w, w, -d, d - 2, 0, h - 15, _wood),
        Box3(-w, w, -d, d, h - 15, h, _white),
        Box3(-w * 0.6, w * 0.6, -d + 8, d - 6, h - 0.5, h + 0.3, const Color(0xFFDDE3E6)),
        Box3(-2, 2, -d + 1, -d + 12, h, h + 22, _chrome),
      ];
    case FixtureType.toilet:
      return [
        Box3(-w * 0.95, w * 0.95, -d, -d + 18, 0, h, _white),
        Box3(-w * 0.8, w * 0.8, -d + 18, d, 0, 38, _white),
        Box3(-w * 0.85, w * 0.85, -d + 18, d, 38, 41, const Color(0xFFE8E8E4)),
      ];
    case FixtureType.shower:
      return [
        Box3(-w, w, -d, d, 0, 5, _white),
        Box3(-w, w, d - 1, d, 5, h, _glass),
        Box3(w - 1, w, -d, d, 5, h, _glass),
        Box3(-3, 3, -d, -d + 4, 100, 190, _chrome),
        Box3(-10, 10, -d, -d + 25, 190, 193, _chrome),
      ];
    case FixtureType.bathtub:
      return [
        Box3(-w, w, -d, d, 0, h, _white),
        Box3(-w + 8, w - 8, -d + 8, d - 8, h - 0.4, h + 0.2, const Color(0xFFBFD9E6)),
        Box3(-w + 4, -w + 9, -2, 2, h, h + 18, _chrome),
      ];
    case FixtureType.washer:
      return [
        Box3(-w, w, -d, d, 0, h, _white),
        Box3(-w * 0.6, w * 0.6, d, d + 1, h * 0.2, h * 0.75, const Color(0xFF4A5560)),
        Box3(-w, w, -d, -d + 12, h, h + 0.5, const Color(0xFFD5D8DB)),
      ];
    case FixtureType.cabinet:
      return [
        Box3(-w, w, -d, d, e, e + h, _wood),
        Box3(-0.5, 0.5, d, d + 0.5, e + 2, e + h - 2, const Color(0xFF6E4F35)),
      ];
    case FixtureType.mirror:
      return [Box3(-w, w, -d, d, e, e + h, const Color(0xFFCFE3EC))];
  }
}

/// Paints the top-view symbol of a fixture. The canvas is in plan centimetres.
void paintFixturePlan(Canvas c, Fixture f, {bool selected = false, double strokeScale = 1}) {
  final w = f.width / 2, d = f.depth / 2;
  c.save();
  c.translate(f.pos.dx, f.pos.dy);
  c.rotate(f.rotation);
  final fill = Paint()..color = Colors.white;
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4 * strokeScale
    ..color = selected ? Colors.orange.shade800 : const Color(0xFF37474F);
  final soft = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1 * strokeScale
    ..color = const Color(0xFF78909C);
  final outer = Rect.fromLTRB(-w, -d, w, d);
  switch (f.type) {
    case FixtureType.sink:
      c.drawRect(outer, fill);
      c.drawRect(outer, line);
      final basin = Rect.fromLTRB(-w * 0.75, -d + 8, w * 0.75, d - 5);
      c.drawOval(basin, soft);
      c.drawCircle(basin.center, 1.5, soft);
      c.drawLine(Offset(0, -d), Offset(0, -d + 10), line);
    case FixtureType.toilet:
      final tank = Rect.fromLTRB(-w * 0.95, -d, w * 0.95, -d + 18);
      final bowl = Rect.fromLTRB(-w * 0.8, -d + 12, w * 0.8, d);
      c.drawOval(bowl, fill);
      c.drawOval(bowl, line);
      c.drawOval(bowl.deflate(5), soft);
      c.drawRRect(RRect.fromRectAndRadius(tank, const Radius.circular(3)), fill);
      c.drawRRect(RRect.fromRectAndRadius(tank, const Radius.circular(3)), line);
    case FixtureType.shower:
      c.drawRect(outer, fill);
      c.drawRect(outer, line);
      c.drawLine(outer.topLeft, outer.bottomRight, soft);
      c.drawLine(outer.topRight, outer.bottomLeft, soft);
      c.drawCircle(Offset.zero, 4, line);
    case FixtureType.bathtub:
      final r = RRect.fromRectAndRadius(outer, const Radius.circular(6));
      c.drawRRect(r, fill);
      c.drawRRect(r, line);
      c.drawRRect(RRect.fromRectAndRadius(outer.deflate(7), Radius.circular(d * 0.7)), soft);
      c.drawCircle(Offset(-w + 16, 0), 2.5, soft);
    case FixtureType.washer:
      c.drawRect(outer, fill);
      c.drawRect(outer, line);
      c.drawCircle(Offset(0, 4), d * 0.6, soft);
    case FixtureType.cabinet:
      c.drawRect(outer, Paint()..color = const Color(0x22000000));
      c.drawRect(outer, soft..strokeWidth = 1 * strokeScale);
      c.drawLine(outer.topLeft, outer.bottomRight, soft);
    case FixtureType.mirror:
      c.drawRect(outer.inflate(1), Paint()..color = const Color(0xFF90CAF9));
  }
  c.restore();
}
