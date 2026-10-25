import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../fixtures.dart';
import '../geometry.dart';
import '../models.dart';
import '../store.dart';
import '../surfaces.dart';
import 'common.dart';
import 'dialogs.dart';
import 'surface_paint.dart';
import '../i18n.dart';

/// Top view of the room. Tap to place corners; double-tap a corner, wall,
/// floor or fixture to edit it.
class PlanEditor extends StatefulWidget {
  final Project project;

  /// Called before every change, so the caller can store an undo snapshot.
  final VoidCallback beforeChange;
  final VoidCallback onChanged;
  final void Function(int wall) openWall;
  final VoidCallback openFloor;

  const PlanEditor({
    super.key,
    required this.project,
    required this.beforeChange,
    required this.onChanged,
    required this.openWall,
    required this.openFloor,
  });

  @override
  State<PlanEditor> createState() => PlanEditorState();
}

enum _Drag { none, pan, point, fixture }

class PlanEditorState extends State<PlanEditor> {
  double _scale = 1.5; // screen px per cm
  Offset _pan = const Offset(40, 60);
  Size _size = Size.zero;
  bool _fitted = false;

  String? _selectedFixture;
  Offset _doubleTapPos = Offset.zero;

  _Drag _drag = _Drag.none;
  int _dragIndex = -1;
  bool _dragMoved = false;
  double _startScale = 1;
  Offset _startFocal = Offset.zero;
  Offset _startPan = Offset.zero;
  int _pointers = 0;

  Project get p => widget.project;
  bool get drawing => !p.closed;

  Offset toScreen(Offset c) => _pan + c * _scale;
  Offset toPlan(Offset s) => (s - _pan) / _scale;

  void fit() {
    if (_size.isEmpty) return;
    final pts = [...p.points, for (final f in p.fixtures) f.pos];
    if (pts.length < 2) {
      _scale = math.min(_size.width, _size.height) / 400;
      _pan = Offset(_size.width / 2, _size.height / 2) - const Offset(200, 200) * _scale;
    } else {
      final b = boundsOf(pts).inflate(40);
      _scale = math.min(_size.width / b.width, (_size.height - 80) / b.height).clamp(0.05, 20.0);
      _pan = Offset(_size.width / 2, (_size.height - 80) / 2) - b.center * _scale;
    }
    setState(() {});
  }

  // ---- hit tests (screen coordinates) ----

  int _hitPoint(Offset s) {
    var best = -1;
    var bestD = 24.0;
    for (var i = 0; i < p.points.length; i++) {
      final d = (toScreen(p.points[i]) - s).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  int _hitEdge(Offset s) {
    var best = -1;
    var bestD = 18.0;
    for (var i = 0; i < p.edgeCount; i++) {
      final d = distToSegment(s, toScreen(p.wallStart(i)), toScreen(p.wallEnd(i)));
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  Fixture? _hitFixture(Offset s) {
    final c = toPlan(s);
    for (final f in p.fixtures.reversed) {
      if (f.contains(c)) return f;
    }
    return null;
  }

  // ---- editing ----

  Offset _snapNew(Offset c) {
    var q = snapTo(c, 1);
    if (p.points.isNotEmpty) {
      final last = p.points.last;
      final d = q - last;
      final len = d.distance;
      if (len > 0) {
        final ang = math.atan2(d.dy, d.dx);
        const step = math.pi / 4;
        final snapped = (ang / step).roundToDouble() * step;
        if ((snapped - ang).abs() < 6 * math.pi / 180) {
          final l = len.roundToDouble();
          q = last + Offset(math.cos(snapped), math.sin(snapped)) * l;
          q = Offset((q.dx * 10).roundToDouble() / 10, (q.dy * 10).roundToDouble() / 10);
        }
      }
    }
    return q;
  }

  void _change(VoidCallback fn) {
    widget.beforeChange();
    fn();
    p.syncWalls();
    widget.onChanged();
    setState(() {});
  }

  void closeRoom() {
    if (p.points.length < 3) return;
    _change(_close);
  }

  /// Closes the plan and, the first time, lays the room's chosen collection.
  void _close() {
    p.closed = true;
    p.syncWalls();
    final store = AppScope.read(context);
    final c = store.collection(p.collectionId);
    final untiled = !p.floor.isTiled && p.walls.every((w) => !w.tiling.isTiled);
    if (c != null && untiled) applyCollection(p, c, store.tileMap);
  }

  void removeLastPoint() {
    if (p.points.isEmpty) return;
    _change(() {
      if (p.closed) {
        p.closed = false;
      } else {
        p.points.removeLast();
      }
    });
  }

  Future<void> addFixture() async {
    final type = await pickFixtureType(context, fixtureIcon);
    if (type == null) return;
    final center = p.points.length >= 3 ? centroid(p.points) : toPlan(Offset(_size.width / 2, _size.height / 2));
    final f = Fixture(type: type, pos: center);
    _change(() {
      p.fixtures.add(f);
      _selectedFixture = f.id;
    });
  }

  /// Snaps a fixture's back against the nearest wall when it is close.
  void _snapFixtureToWall(Fixture f) {
    if (!p.closed) return;
    double bestD = double.infinity;
    for (var i = 0; i < p.edgeCount; i++) {
      final a = p.wallStart(i), b = p.wallEnd(i);
      final ab = b - a;
      final len = ab.distance;
      if (len == 0) continue;
      final t = dot(f.pos - a, ab) / (len * len);
      if (t < 0 || t > 1) continue;
      final proj = a + ab * t;
      final dist = (f.pos - proj).distance;
      if (dist < f.depth / 2 + 20 && dist < bestD) {
        bestD = dist;
        final n = inwardNormal(p.points, i);
        f.rotation = math.atan2(-n.dx, n.dy);
        f.pos = proj + n * (f.depth / 2);
      }
    }
  }

  // ---- gestures ----

  void _onTapUp(TapUpDetails d) {
    final s = d.localPosition;
    if (drawing) {
      if (p.points.length >= 3 && (toScreen(p.points.first) - s).distance < 24) {
        closeRoom();
        return;
      }
      final c = _snapNew(toPlan(s));
      _change(() => p.points.add(c));
      return;
    }
    final f = _hitFixture(s);
    setState(() => _selectedFixture = f?.id);
  }

  Future<void> _onDoubleTap() async {
    final s = _doubleTapPos;
    final store = AppScope.read(context);
    final pi = _hitPoint(s);
    final n = p.points.length;
    if (pi >= 0 && (p.closed ? n >= 3 : (pi > 0 && pi < n - 1))) {
      final cur = interiorAngle(p.points, pi, closed: p.closed);
      final v = await showAngleDialog(context, cur);
      if (v != null) _change(() => p.points = setVertexAngle(p.points, pi, v, closed: p.closed));
      return;
    }
    final f = _hitFixture(s);
    if (f != null) {
      setState(() => _selectedFixture = f.id);
      widget.beforeChange();
      final r = await showFixtureDialog(context, f);
      if (r == 'delete') p.fixtures.remove(f);
      if (r != null) {
        widget.onChanged();
        setState(() {});
      }
      return;
    }
    final e = _hitEdge(s);
    if (e >= 0) {
      final r = await showWallDialog(context, p, e);
      if (r == null) return;
      _change(() {
        if ((r.length - p.wallLength(e)).abs() > 0.05) {
          p.points = setEdgeLength(p.points, e, r.length, closed: p.closed);
        }
        p.walls[e].height = r.height;
        r.layout.applyToBase(p.walls[e].tiling);
      });
      if (r.openWall) widget.openWall(e);
      return;
    }
    if (p.closed && pointInPolygon(toPlan(s), p.points)) {
      final b = boundsOf(p.points);
      final r = await showFloorDialog(context, p, b.size);
      if (r == null) return;
      _change(() {
        final sx = b.width == 0 ? 1.0 : r.width / b.width, sy = b.height == 0 ? 1.0 : r.height / b.height;
        if ((sx - 1).abs() > 1e-4 || (sy - 1).abs() > 1e-4) {
          p.points = [for (final q in p.points) Offset(b.left + (q.dx - b.left) * sx, b.top + (q.dy - b.top) * sy)];
        }
        r.layout.applyToBase(p.floor);
      });
      if (r.openFloor) widget.openFloor();
    }
    store.scheduleSave();
  }

  Future<void> _onLongPress(LongPressStartDetails d) async {
    final s = d.localPosition;
    final pi = _hitPoint(s);
    if (pi >= 0) {
      if (p.closed && p.points.length <= 3) return;
      final ok = await confirm(
        context,
        tr('Remove corner?'),
        tr('The two walls next to it become one.'),
        ok: tr('Remove'),
      );
      if (ok) {
        _change(() {
          p.points.removeAt(pi);
          if (pi < p.walls.length) p.walls.removeAt(pi);
        });
      }
      return;
    }
    final e = _hitEdge(s);
    if (e >= 0) {
      final a = p.wallStart(e), b = p.wallEnd(e);
      final ab = b - a;
      final t = (dot(toPlan(s) - a, ab) / dot(ab, ab)).clamp(0.05, 0.95);
      _change(() {
        p.points.insert(e + 1, snapTo(a + ab * t, 1));
        final old = p.walls[e];
        p.walls.insert(
          e + 1,
          Wall(
            height: old.height,
            tiling: SurfaceTiling(tileId: old.tiling.tileId),
          ),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Corner added. Drag it into place.')), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _pointers = d.pointerCount;
    _startScale = _scale;
    _startFocal = d.localFocalPoint;
    _startPan = _pan;
    _dragMoved = false;
    _drag = _Drag.pan;
    if (d.pointerCount == 1) {
      final pi = _hitPoint(d.localFocalPoint);
      if (pi >= 0) {
        _drag = _Drag.point;
        _dragIndex = pi;
        return;
      }
      final f = _hitFixture(d.localFocalPoint);
      if (f != null && (f.id == _selectedFixture || !drawing)) {
        _drag = _Drag.fixture;
        _dragIndex = p.fixtures.indexOf(f);
        _selectedFixture = f.id;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _pointers) {
      // Finger added or lifted: restart as a pan/zoom from here.
      _pointers = d.pointerCount;
      _startScale = _scale / d.scale;
      _startFocal = d.localFocalPoint;
      _startPan = _pan;
      _drag = _Drag.pan;
    }
    switch (_drag) {
      case _Drag.point:
        if (!_dragMoved) widget.beforeChange();
        _dragMoved = true;
        var c = snapTo(toPlan(d.localFocalPoint), 1);
        final n = p.points.length;
        final tol = 8 / _scale;
        for (final j in [_dragIndex - 1, _dragIndex + 1]) {
          if (!p.closed && (j < 0 || j >= n)) continue;
          final q = p.points[(j + n) % n];
          if ((c.dx - q.dx).abs() < tol) c = Offset(q.dx, c.dy);
          if ((c.dy - q.dy).abs() < tol) c = Offset(c.dx, q.dy);
        }
        setState(() => p.points[_dragIndex] = c);
      case _Drag.fixture:
        if (!_dragMoved) widget.beforeChange();
        _dragMoved = true;
        final f = p.fixtures[_dragIndex];
        setState(() {
          f.pos = snapTo(toPlan(d.localFocalPoint), 1);
          _snapFixtureToWall(f);
        });
      case _Drag.pan:
        setState(() {
          _scale = (_startScale * d.scale).clamp(0.05, 30.0);
          final planAtStart = (_startFocal - _startPan) / _startScale;
          _pan = d.localFocalPoint - planAtStart * _scale;
        });
      case _Drag.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if ((_drag == _Drag.point || _drag == _Drag.fixture) && _dragMoved) widget.onChanged();
    _drag = _Drag.none;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return LayoutBuilder(
      builder: (context, cons) {
        _size = cons.biggest;
        if (!_fitted) {
          _fitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => fit());
        }
        return Listener(
          onPointerSignal: (e) {
            // Mouse wheel zoom, handy in the web preview.
            if (e is PointerScrollEvent) {
              final planAt = toPlan(e.localPosition);
              setState(() {
                _scale = (_scale * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.05, 30.0);
                _pan = e.localPosition - planAt * _scale;
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
            onDoubleTap: _onDoubleTap,
            onLongPressStart: _onLongPress,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: CustomPaint(
              size: _size,
              painter: _PlanPainter(
                project: p,
                store: store,
                scale: _scale,
                pan: _pan,
                selectedFixture: _selectedFixture,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlanPainter extends CustomPainter {
  final Project project;
  final AppStore store;
  final double scale;
  final Offset pan;
  final String? selectedFixture;

  _PlanPainter({
    required this.project,
    required this.store,
    required this.scale,
    required this.pan,
    required this.selectedFixture,
  });

  Offset sc(Offset c) => pan + c * scale;

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    double size = 12,
    Color color = const Color(0xFF263238),
    bool bg = true,
    FontWeight weight = FontWeight.w500,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(center: at, width: tp.width + 8, height: tp.height + 2);
    if (bg) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = const Color(0xE6FFFFFF));
    }
    tp.paint(canvas, r.topLeft + const Offset(4, 1));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = project;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF7F8F6));
    _grid(canvas, size);

    final pts = p.points;
    // Floor and fixtures, drawn in plan centimetres.
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);
    if (p.closed && pts.length >= 3) {
      paintSurface(canvas, store, SurfaceModel.floor(p), plain: const Color(0xFFE6E2DA));
    }
    for (final f in p.fixtures) {
      paintFixturePlan(canvas, f, selected: f.id == selectedFixture, strokeScale: 1 / scale);
    }
    canvas.restore();

    // Walls.
    for (var i = 0; i < p.edgeCount; i++) {
      final a = sc(p.wallStart(i)), b = sc(p.wallEnd(i));
      final w = p.walls[i];
      final tile =
          store.tile(w.tiling.tileId) ??
          (w.tiling.regions.isNotEmpty ? store.tile(w.tiling.regions.first.tileId) : null);
      if (w.tiling.isTiled) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF263238)
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = tile?.color ?? const Color(0xFF90A4AE)
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xFF455A64)
            ..strokeWidth = 1.6,
        );
      }
      _openings(canvas, i);
    }

    // Labels.
    for (var i = 0; i < p.edgeCount; i++) {
      final a = p.wallStart(i), b = p.wallEnd(i);
      final len = p.wallLength(i);
      if (len * scale < 24) continue;
      var n = p.closed && pts.length >= 3 ? inwardNormal(pts, i) : Offset.zero;
      if (n == Offset.zero) {
        final d = b - a;
        n = Offset(-d.dy, d.dx) / d.distance;
      }
      final mid = sc((a + b) / 2) - n * 18;
      _text(canvas, fmtNum((len * 10).roundToDouble() / 10), mid);
      if (p.closed) {
        _text(
          canvas,
          tr('W{n}', {'n': i + 1}),
          sc((a + b) / 2) + n * 16,
          size: 10,
          color: const Color(0xFF607D8B),
          bg: false,
          weight: FontWeight.w600,
        );
      }
    }
    if (pts.length >= 3) {
      final n = pts.length;
      for (var i = 0; i < n; i++) {
        if (!p.closed && (i == 0 || i == n - 1)) continue;
        final ang = interiorAngle(pts, i, closed: p.closed);
        final prev = pts[(i - 1 + n) % n], next = pts[(i + 1) % n];
        final u1 = (prev - pts[i]), u2 = (next - pts[i]);
        if (u1.distance == 0 || u2.distance == 0) continue;
        var bis = u1 / u1.distance + u2 / u2.distance;
        if (bis.distance < 1e-3) bis = Offset(-u2.dy, u2.dx);
        bis = bis / bis.distance;
        if (p.closed && !pointInPolygon(pts[i] + bis * 2, pts)) bis = -bis;
        final rounded = (ang * 10).roundToDouble() / 10;
        final txt = '${fmtNum(rounded)}°';
        final isRight = (rounded - 90).abs() < 0.05 || (rounded - 270).abs() < 0.05;
        _text(
          canvas,
          txt,
          sc(pts[i]) + bis * 26,
          size: 10,
          color: isRight ? const Color(0xFF90A4AE) : const Color(0xFFD84315),
          bg: false,
        );
      }
    }

    // Corners.
    for (var i = 0; i < pts.length; i++) {
      final s = sc(pts[i]);
      final first = !p.closed && i == 0 && pts.length >= 3;
      canvas.drawCircle(s, first ? 10 : 6, Paint()..color = first ? const Color(0xFF1F6F78) : Colors.white);
      canvas.drawCircle(
        s,
        first ? 10 : 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF1F6F78),
      );
    }
  }

  void _openings(Canvas canvas, int i) {
    final p = project;
    final a = p.wallStart(i), b = p.wallEnd(i);
    final len = p.wallLength(i);
    if (len == 0) return;
    final dir = (b - a) / len;
    final n = p.closed && p.points.length >= 3 ? inwardNormal(p.points, i) : Offset(-dir.dy, dir.dx);
    for (final o in p.walls[i].openings) {
      final x0 = o.x.clamp(0.0, len), x1 = (o.x + o.width).clamp(0.0, len);
      final s0 = sc(a + dir * x0), s1 = sc(a + dir * x1);
      if (o.type == OpeningType.door) {
        canvas.drawLine(
          s0,
          s1,
          Paint()
            ..color = const Color(0xFFF7F8F6)
            ..strokeWidth = 11,
        );
        final r = (x1 - x0) * scale;
        final leaf = s0 + n * r;
        canvas.drawLine(
          s0,
          leaf,
          Paint()
            ..color = const Color(0xFF6D4C41)
            ..strokeWidth = 2,
        );
        final start = math.atan2(n.dy, n.dx);
        final sweepTo = math.atan2(dir.dy, dir.dx);
        var sweep = sweepTo - start;
        while (sweep > math.pi) {
          sweep -= 2 * math.pi;
        }
        while (sweep < -math.pi) {
          sweep += 2 * math.pi;
        }
        canvas.drawArc(
          Rect.fromCircle(center: s0, radius: r),
          start,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF8D6E63),
        );
      } else {
        canvas.drawLine(
          s0,
          s1,
          Paint()
            ..color = const Color(0xFFE1F5FE)
            ..strokeWidth = 8,
        );
        canvas.drawLine(
          s0,
          s1,
          Paint()
            ..color = const Color(0xFF0288D1)
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  void _grid(Canvas canvas, Size size) {
    final tl = (Offset.zero - pan) / scale, br = (Offset(size.width, size.height) - pan) / scale;
    void lines(double step, Paint paint) {
      for (var x = (tl.dx / step).floor() * step; x <= br.dx; x += step) {
        canvas.drawLine(Offset(pan.dx + x * scale, 0), Offset(pan.dx + x * scale, size.height), paint);
      }
      for (var y = (tl.dy / step).floor() * step; y <= br.dy; y += step) {
        canvas.drawLine(Offset(0, pan.dy + y * scale), Offset(size.width, pan.dy + y * scale), paint);
      }
    }

    if (10 * scale > 8) lines(10, Paint()..color = const Color(0xFFECEFEA));
    lines(100, Paint()..color = const Color(0xFFD5DBD3));
  }

  @override
  bool shouldRepaint(covariant _PlanPainter old) => true;
}
