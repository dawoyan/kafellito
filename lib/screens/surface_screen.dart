import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../fixtures.dart';
import '../geometry.dart';
import '../models.dart';
import '../store.dart';
import '../surfaces.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/surface_paint.dart';
import '../i18n.dart';

enum SurfaceTool { select, polygon, rect }

/// Edits one wall (when [wallIndex] is set) or the floor: tiled areas,
/// doors, windows and fixtures against the wall.
class SurfaceScreen extends StatefulWidget {
  final Project project;
  final int? wallIndex;
  final VoidCallback beforeChange;
  final VoidCallback onChanged;

  const SurfaceScreen({
    super.key,
    required this.project,
    required this.wallIndex,
    required this.beforeChange,
    required this.onChanged,
  });

  @override
  State<SurfaceScreen> createState() => _SurfaceScreenState();
}

enum _Drag { none, pan, vertex, region, opening, fixture, rect }

class _SurfaceScreenState extends State<SurfaceScreen> {
  late int? _wall = widget.wallIndex;
  SurfaceTool _tool = SurfaceTool.select;
  double _scale = 1;
  Offset _pan = Offset.zero;
  Size _size = Size.zero;
  bool _fitted = false;

  final List<Offset> _draft = [];
  Rect? _draftRect;
  String? _selRegion;
  String? _selOpening;

  _Drag _drag = _Drag.none;
  int _dragIndex = -1;
  Offset _dragLast = Offset.zero;
  bool _dragMoved = false;
  Offset _doubleTapPos = Offset.zero;
  double _startScale = 1;
  Offset _startFocal = Offset.zero, _startPan = Offset.zero;
  int _pointers = 0;

  Project get p => widget.project;
  bool get isWall => _wall != null;
  SurfaceModel get model => isWall ? SurfaceModel.wall(p, _wall!) : SurfaceModel.floor(p);
  SurfaceTiling get tiling => isWall ? p.walls[_wall!].tiling : p.floor;

  /// -1 when the wall is drawn flipped so it reads as seen from inside.
  double get _sx => isWall && wallMirrored(p, _wall!) ? -1 : 1;

  Offset toScreen(Offset c) => _pan + Offset(c.dx * _sx, isWall ? -c.dy : c.dy) * _scale;
  Offset toSurf(Offset s) {
    final q = (s - _pan) / _scale;
    return Offset(q.dx * _sx, isWall ? -q.dy : q.dy);
  }

  void _fit() {
    if (_size.isEmpty) return;
    final b = model.bounds;
    final avail = Size(_size.width - 48, _size.height - 140);
    _scale = math.min(avail.width / math.max(b.width, 1), avail.height / math.max(b.height, 1)).clamp(0.05, 30.0);
    final center = Offset(_size.width / 2, (_size.height - 60) / 2);
    final bc = b.center;
    _pan = center - Offset(bc.dx * _sx, isWall ? -bc.dy : bc.dy) * _scale;
    setState(() {});
  }

  void _change(VoidCallback fn) {
    widget.beforeChange();
    fn();
    widget.onChanged();
    setState(() {});
  }

  // ---- fixtures projected on the wall ----

  /// Fixtures standing against this wall, with their extent in wall coordinates.
  List<(Fixture, Rect)> _wallFixtures() {
    if (!isWall) return [];
    final i = _wall!;
    final a = p.wallStart(i), b = p.wallEnd(i);
    final len = p.wallLength(i);
    if (len == 0 || p.points.length < 3) return [];
    final dir = (b - a) / len;
    final n = inwardNormal(p.points, i);
    final out = <(Fixture, Rect)>[];
    for (final f in p.fixtures) {
      final cs = [
        f.toPlan(-f.width / 2, -f.depth / 2),
        f.toPlan(f.width / 2, -f.depth / 2),
        f.toPlan(f.width / 2, f.depth / 2),
        f.toPlan(-f.width / 2, f.depth / 2),
      ];
      final us = cs.map((c) => dot(c - a, dir)).toList();
      final ds = cs.map((c) => dot(c - a, n)).toList();
      if (ds.reduce(math.min) > 30 || ds.reduce(math.max) < -5) continue;
      final u0 = us.reduce(math.min), u1 = us.reduce(math.max);
      if (u1 < 0 || u0 > len) continue;
      out.add((f, Rect.fromLTRB(u0, f.elevation, u1, f.elevation + f.height)));
    }
    return out;
  }

  Future<void> _addFixture() async {
    final type = await pickFixtureType(context, fixtureIcon);
    if (type == null || !isWall) return;
    final i = _wall!;
    final a = p.wallStart(i), b = p.wallEnd(i);
    final len = p.wallLength(i);
    final dir = (b - a) / len;
    final n = inwardNormal(p.points, i);
    final f = Fixture(type: type, pos: Offset.zero);
    f.rotation = math.atan2(-n.dx, n.dy);
    f.pos = a + dir * (len / 2) + n * (f.depth / 2);
    _change(() => p.fixtures.add(f));
  }

  void _addOpening(OpeningType type) {
    if (!isWall) return;
    final len = p.wallLength(_wall!);
    final o = type == OpeningType.door
        ? Opening(type: type, width: 80, height: 205)
        : Opening(type: type, width: 100, height: 120, y: 90);
    o.x = math.max(0, (len - o.width) / 2).roundToDouble();
    _change(() {
      p.walls[_wall!].openings.add(o);
      _selOpening = o.id;
    });
  }

  // ---- hit tests ----

  Region? _hitRegion(Offset s) {
    final c = toSurf(s);
    for (final r in tiling.regions.reversed) {
      if (r.points.length >= 3 && pointInPolygon(c, r.points)) return r;
    }
    return null;
  }

  Opening? _hitOpening(Offset s) {
    if (!isWall) return null;
    final c = toSurf(s);
    for (final o in p.walls[_wall!].openings.reversed) {
      if (o.rect.contains(c)) return o;
    }
    return null;
  }

  (Fixture, Rect)? _hitFixture(Offset s) {
    final c = toSurf(s);
    for (final e in _wallFixtures().reversed) {
      if (e.$2.contains(c)) return e;
    }
    return null;
  }

  int _hitVertex(Offset s) {
    final r = tiling.regions.where((r) => r.id == _selRegion).firstOrNull;
    if (r == null) return -1;
    for (var i = 0; i < r.points.length; i++) {
      if ((toScreen(r.points[i]) - s).distance < 22) return i;
    }
    return -1;
  }

  Offset _snap(Offset c) {
    var q = snapTo(c, 1);
    final cands = <Offset>[...model.base, for (final r in tiling.regions) ...r.points, ..._draft];
    for (final o in isWall ? p.walls[_wall!].openings : <Opening>[]) {
      final r = o.rect;
      cands.addAll([r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]);
    }
    final tol = 12 / _scale;
    for (final k in cands) {
      if ((k - c).distance < tol) return k;
    }
    for (final k in cands) {
      if ((k.dx - q.dx).abs() < tol * 0.7) q = Offset(k.dx, q.dy);
      if ((k.dy - q.dy).abs() < tol * 0.7) q = Offset(q.dx, k.dy);
    }
    return q;
  }

  // ---- gestures ----

  Future<void> _finishRegion(List<Offset> pts) async {
    final last = tiling.regions.lastOrNull;
    final choice = await showRegionDialog(
      context,
      p,
      model,
      last == null ? LayoutChoice() : LayoutChoice.ofRegion(last),
      newPoints: pts,
    );
    setState(() {
      _draft.clear();
      _draftRect = null;
    });
    if (choice?.tileId == null) return;
    final r = Region(points: pts, tileId: choice!.tileId!);
    choice.applyToRegion(r);
    _change(() {
      tiling.regions.add(r);
      _selRegion = r.id;
      _tool = SurfaceTool.select;
    });
  }

  void _onTapUp(TapUpDetails d) {
    final s = d.localPosition;
    if (_tool == SurfaceTool.polygon) {
      if (_draft.length >= 3 && (toScreen(_draft.first) - s).distance < 24) {
        _finishRegion(List.of(_draft));
        return;
      }
      setState(() => _draft.add(_snap(toSurf(s))));
      return;
    }
    if (_tool == SurfaceTool.select) {
      final o = _hitOpening(s);
      final r = o == null ? _hitRegion(s) : null;
      setState(() {
        _selOpening = o?.id;
        _selRegion = r?.id;
      });
    }
  }

  Future<void> _onDoubleTap() async {
    if (_tool != SurfaceTool.select) return;
    final s = _doubleTapPos;
    final o = _hitOpening(s);
    if (o != null) {
      widget.beforeChange();
      final r = await showOpeningDialog(context, o, p.wallLength(_wall!), mirrored: _sx < 0);
      if (r == 'delete') p.walls[_wall!].openings.remove(o);
      if (r != null) {
        widget.onChanged();
        setState(() {});
      }
      return;
    }
    final fx = _hitFixture(s);
    if (fx != null) {
      widget.beforeChange();
      final r = await showFixtureDialog(context, fx.$1);
      if (r == 'delete') p.fixtures.remove(fx.$1);
      if (r != null) {
        widget.onChanged();
        setState(() {});
      }
      return;
    }
    final reg = _hitRegion(s);
    if (reg != null) {
      final r = await showRegionDialog(
        context,
        p,
        model,
        LayoutChoice.ofRegion(reg),
        index: tiling.regions.indexOf(reg),
      );
      if (r == null) return;
      _change(() {
        if (r.tileId == null) {
          tiling.regions.remove(reg);
        } else {
          r.applyToRegion(reg);
        }
      });
      return;
    }
    if (model.classify(toSurf(s)) != null) await _editBase();
  }

  Future<void> _editBase() async {
    final choice = await showBaseTileDialog(context, p, model);
    if (choice != null) _change(() => choice.applyToBase(tiling));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _pointers = d.pointerCount;
    _startScale = _scale;
    _startFocal = d.localFocalPoint;
    _startPan = _pan;
    _dragMoved = false;
    _dragLast = toSurf(d.localFocalPoint);
    _drag = _Drag.pan;
    if (d.pointerCount != 1) return;
    final s = d.localFocalPoint;
    if (_tool == SurfaceTool.rect) {
      _drag = _Drag.rect;
      final c = _snap(toSurf(s));
      _draftRect = Rect.fromPoints(c, c);
      return;
    }
    if (_tool != SurfaceTool.select) return;
    final v = _hitVertex(s);
    if (v >= 0) {
      _drag = _Drag.vertex;
      _dragIndex = v;
      return;
    }
    final o = _hitOpening(s);
    if (o != null) {
      _drag = _Drag.opening;
      _selOpening = o.id;
      _selRegion = null;
      return;
    }
    final fx = _hitFixture(s);
    if (fx != null) {
      _drag = _Drag.fixture;
      _dragIndex = p.fixtures.indexOf(fx.$1);
      return;
    }
    final r = _hitRegion(s);
    if (r != null && r.id == _selRegion) {
      _drag = _Drag.region;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount != _pointers) {
      _pointers = d.pointerCount;
      _startScale = _scale / d.scale;
      _startFocal = d.localFocalPoint;
      _startPan = _pan;
      _drag = _Drag.pan;
      _draftRect = null;
    }
    final c = toSurf(d.localFocalPoint);
    final delta = c - _dragLast;
    if (_drag != _Drag.pan && _drag != _Drag.rect && !_dragMoved) widget.beforeChange();
    _dragMoved = true;
    setState(() {
      switch (_drag) {
        case _Drag.pan:
          _scale = (_startScale * d.scale).clamp(0.05, 30.0);
          final atStart = (_startFocal - _startPan) / _startScale;
          _pan = d.localFocalPoint - atStart * _scale;
        case _Drag.rect:
          _draftRect = Rect.fromPoints(_rectStart ?? c, _snap(c));
        case _Drag.vertex:
          final r = tiling.regions.firstWhere((r) => r.id == _selRegion);
          r.points[_dragIndex] = _snap(c);
        case _Drag.region:
          final r = tiling.regions.firstWhere((r) => r.id == _selRegion);
          final step = snapTo(delta, 1);
          if (step != Offset.zero) {
            r.points = [for (final q in r.points) q + step];
            _dragLast += step;
          }
          return;
        case _Drag.opening:
          final o = p.walls[_wall!].openings.firstWhere((o) => o.id == _selOpening);
          final step = snapTo(delta, 1);
          if (step != Offset.zero) {
            final len = p.wallLength(_wall!);
            o.x = (o.x + step.dx).clamp(-o.width + 5, len - 5);
            o.y = math.max(0, o.y + step.dy);
            _dragLast += step;
          }
          return;
        case _Drag.fixture:
          final f = p.fixtures[_dragIndex];
          final i = _wall!;
          final dir = (p.wallEnd(i) - p.wallStart(i)) / p.wallLength(i);
          final step = delta.dx.roundToDouble();
          if (step != 0) {
            f.pos += dir * step;
            _dragLast += Offset(step, 0);
          }
          return;
        case _Drag.none:
          break;
      }
      _dragLast = c;
    });
  }

  Offset? _rectStart;

  void _onScaleEnd(ScaleEndDetails d) {
    if (_drag == _Drag.rect && _draftRect != null) {
      final r = _draftRect!;
      _rectStart = null;
      if (r.width >= 2 && r.height >= 2) {
        _finishRegion([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
      } else {
        setState(() => _draftRect = null);
      }
    } else if (_drag != _Drag.pan && _drag != _Drag.none && _dragMoved) {
      widget.onChanged();
    }
    _drag = _Drag.none;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final title = isWall
        ? '${tr('Wall {n}', {'n': _wall! + 1})} · ${fmtNum(p.wallLength(_wall!).roundToDouble())} × ${fmtNum(p.walls[_wall!].height)} ${tr('cm')}'
        : tr('Floor');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isWall) ...[
            IconButton(
              tooltip: tr('Previous wall'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() {
                _wall = (_wall! - 1 + p.edgeCount) % p.edgeCount;
                _selRegion = _selOpening = null;
                _draft.clear();
                WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
              }),
            ),
            IconButton(
              tooltip: tr('Next wall'),
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() {
                _wall = (_wall! + 1) % p.edgeCount;
                _selRegion = _selOpening = null;
                _draft.clear();
                WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
              }),
            ),
          ],
          IconButton(
            tooltip: tr('Whole surface tile'),
            icon: const Icon(Icons.format_color_fill),
            onPressed: _editBase,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                _size = cons.biggest;
                if (!_fitted) {
                  _fitted = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
                }
                return Stack(
                  children: [
                    Listener(
                      onPointerSignal: (e) {
                        if (e is PointerScrollEvent) {
                          final q = (e.localPosition - _pan) / _scale;
                          setState(() {
                            _scale = (_scale * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.05, 30.0);
                            _pan = e.localPosition - q * _scale;
                          });
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _onTapUp,
                        onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                        onDoubleTap: _onDoubleTap,
                        onScaleStart: (d) {
                          if (_tool == SurfaceTool.rect) _rectStart = _snap(toSurf(d.localFocalPoint));
                          _onScaleStart(d);
                        },
                        onScaleUpdate: _onScaleUpdate,
                        onScaleEnd: _onScaleEnd,
                        child: CustomPaint(
                          size: _size,
                          painter: _SurfacePainter(
                            state: this,
                            store: store,
                            model: model,
                            fixtures: _wallFixtures(),
                            floorFixtures: isWall ? const [] : p.fixtures,
                          ),
                        ),
                      ),
                    ),
                    Positioned(left: 12, right: 12, top: 8, child: _hint()),
                  ],
                );
              },
            ),
          ),
          _toolbar(),
        ],
      ),
    );
  }

  Widget _hint() {
    final text = switch (_tool) {
      SurfaceTool.polygon =>
        _draft.length < 3
            ? tr('Tap to place the corners of the area.')
            : tr('Tap the first corner to finish the area.'),
      SurfaceTool.rect => tr('Drag to draw a rectangle.'),
      SurfaceTool.select => tr('Double-tap an area, door or the wall to edit it. Drag to move.'),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xE6FFFFFF), borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  Widget _toolbar() {
    Widget tool(SurfaceTool t, IconData icon, String label) => ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: _tool == t,
      onSelected: (_) => setState(() {
        _tool = t;
        _draft.clear();
        _draftRect = null;
      }),
    );
    return Material(
      elevation: 6,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              tool(SurfaceTool.select, Icons.pan_tool_alt_outlined, tr('Select')),
              gap(6),
              tool(SurfaceTool.rect, Icons.crop_square, tr('Rectangle')),
              gap(6),
              tool(SurfaceTool.polygon, Icons.polyline_outlined, tr('Shape')),
              if (_tool == SurfaceTool.polygon && _draft.isNotEmpty) ...[
                gap(6),
                IconButton(
                  tooltip: tr('Undo point'),
                  onPressed: () => setState(() => _draft.removeLast()),
                  icon: const Icon(Icons.undo),
                ),
              ],
              if (isWall) ...[
                const SizedBox(width: 16),
                ActionChip(
                  avatar: const Icon(Icons.door_front_door_outlined, size: 18),
                  label: Text(tr('Door')),
                  onPressed: () => _addOpening(OpeningType.door),
                ),
                gap(6),
                ActionChip(
                  avatar: const Icon(Icons.window_outlined, size: 18),
                  label: Text(tr('Window')),
                  onPressed: () => _addOpening(OpeningType.window),
                ),
                gap(6),
                ActionChip(
                  avatar: const Icon(Icons.bathtub_outlined, size: 18),
                  label: Text(tr('Fixture')),
                  onPressed: _addFixture,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SurfacePainter extends CustomPainter {
  final _SurfaceScreenState state;
  final AppStore store;
  final SurfaceModel model;
  final List<(Fixture, Rect)> fixtures;
  final List<Fixture> floorFixtures;

  _SurfacePainter({
    required this.state,
    required this.store,
    required this.model,
    required this.fixtures,
    required this.floorFixtures,
  });

  void _text(Canvas c, String s, Offset at, {double size = 11, Color color = const Color(0xFF37474F)}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(center: at, width: tp.width + 8, height: tp.height + 2);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = const Color(0xD9FFFFFF));
    tp.paint(c, r.topLeft + const Offset(4, 1));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final isWall = s.isWall;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF1F3F0));
    final scale = s._scale;

    canvas.save();
    canvas.translate(s._pan.dx, s._pan.dy);
    canvas.scale(scale * s._sx, isWall ? -scale : scale);
    paintSurface(
      canvas,
      store,
      model,
      plain: isWall ? const Color(0xFFF4EFE6) : const Color(0xFFE6E2DA),
      flipY: isWall,
      flipX: s._sx < 0,
    );
    canvas.drawPath(
      Path()..addPolygon(model.base, true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale
        ..color = const Color(0xFF37474F),
    );
    for (final f in floorFixtures) {
      paintFixturePlan(canvas, f, strokeScale: 1 / scale);
    }
    canvas.restore();

    // Openings.
    if (isWall) {
      for (final o in s.p.walls[s._wall!].openings) {
        final r = Rect.fromPoints(s.toScreen(o.rect.topLeft), s.toScreen(o.rect.bottomRight));
        final sel = o.id == s._selOpening;
        canvas.drawRect(
          r,
          Paint()..color = o.type == OpeningType.door ? const Color(0xFFBCAAA4) : const Color(0xFFB3E5FC),
        );
        canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 3 : 1.5
            ..color = sel ? Colors.orange.shade800 : const Color(0xFF5D4037),
        );
        if (o.type == OpeningType.door) {
          canvas.drawCircle(Offset(r.right - 10, r.center.dy), 3, Paint()..color = const Color(0xFF5D4037));
        } else {
          canvas.drawLine(r.topCenter, r.bottomCenter, Paint()..color = const Color(0xFF0277BD));
        }
        _text(canvas, '${fmtNum(o.width)}×${fmtNum(o.height)}', r.center);
      }
      // Fixtures against this wall.
      for (final (f, rect) in fixtures) {
        final r = Rect.fromPoints(s.toScreen(rect.topLeft), s.toScreen(rect.bottomRight));
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()..color = const Color(0x99FFFFFF),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFF455A64),
        );
        final icon = fixtureIcon(f.type);
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: math.min(36, math.min(r.width, r.height) * 0.6),
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: const Color(0xFF455A64),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Regions: outline the selected one with handles.
    for (final r in model.tiling.regions) {
      final sel = r.id == s._selRegion;
      final path = Path()..addPolygon(r.points.map(s.toScreen).toList(), true);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 2.5 : 1
          ..color = sel ? Colors.orange.shade800 : const Color(0x88263238),
      );
      if (sel) {
        for (final q in r.points) {
          canvas.drawCircle(s.toScreen(q), 7, Paint()..color = Colors.white);
          canvas.drawCircle(
            s.toScreen(q),
            7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.orange.shade800,
          );
        }
      }
    }

    // Drafts.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF1F6F78);
    if (s._draft.isNotEmpty) {
      final pts = s._draft.map(s.toScreen).toList();
      canvas.drawPath(Path()..addPolygon(pts, false), line);
      for (var i = 0; i < pts.length; i++) {
        canvas.drawCircle(pts[i], i == 0 ? 10 : 6, Paint()..color = i == 0 ? const Color(0xFF1F6F78) : Colors.white);
        canvas.drawCircle(pts[i], i == 0 ? 10 : 6, line);
      }
    }
    if (s._draftRect != null) {
      final r = Rect.fromPoints(s.toScreen(s._draftRect!.topLeft), s.toScreen(s._draftRect!.bottomRight));
      canvas.drawRect(r, Paint()..color = const Color(0x331F6F78));
      canvas.drawRect(r, line);
      _text(canvas, '${fmtNum(s._draftRect!.width)}×${fmtNum(s._draftRect!.height)}', r.center);
    }

    // Dimensions.
    final b = model.bounds;
    if (isWall) {
      _text(
        canvas,
        '${fmtNum((b.width * 10).roundToDouble() / 10)} ${tr('cm')}',
        s.toScreen(Offset(b.center.dx, 0)) + const Offset(0, 16),
      );
      final left = s._sx < 0 ? b.right : b.left;
      _text(canvas, '${fmtNum(b.height)} ${tr('cm')}', s.toScreen(Offset(left, b.center.dy)) - const Offset(30, 0));
    } else {
      _text(
        canvas,
        '${fmtNum((b.width * 10).roundToDouble() / 10)} ${tr('cm')}',
        s.toScreen(Offset(b.center.dx, b.bottom)) + const Offset(0, 16),
      );
      _text(
        canvas,
        '${fmtNum((b.height * 10).roundToDouble() / 10)} ${tr('cm')}',
        s.toScreen(Offset(b.left, b.center.dy)) - const Offset(30, 0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SurfacePainter old) => true;
}
