import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../fixtures.dart';
import '../geometry.dart';
import '../models.dart';
import '../store.dart';
import '../surfaces.dart';
import '../i18n.dart';

/// World space: x = plan x, y = up, z = -plan y (so the view is not mirrored).
Vector3 _w(Offset plan, double h) => Vector3(plan.dx, h, -plan.dy);

const _doorKey = '#door';
const _windowKey = '#window';
const _ceilingKey = '#ceiling';

class _Quad {
  final List<Vector3> pos;
  final List<Offset> uv; // surface cm, texture-oriented
  final String key;
  _Quad(this.pos, this.uv, this.key);
}

class _SurfaceMesh {
  final List<_Quad> quads;
  final Vector3 center;
  final double shade;
  // Walls are culled when seen from behind.
  final Offset? wallA;
  final Offset? wallNormal;
  final bool isFloor;
  final bool isCeiling;
  _SurfaceMesh(
    this.quads,
    this.center,
    this.shade, {
    this.wallA,
    this.wallNormal,
    this.isFloor = false,
    this.isCeiling = false,
  });
}

class _Face {
  final List<Vector3> pos;
  final Color color;
  final Vector3 normal;
  _Face(this.pos, this.color, this.normal);
}

class _RoomMesh {
  final List<_SurfaceMesh> surfaces;
  final List<_Face> faces;
  _RoomMesh(this.surfaces, this.faces);

  static _RoomMesh build(Project p) {
    final surfaces = <_SurfaceMesh>[];
    final light = const Offset(0.6, -0.8);
    for (final s in SurfaceModel.all(p)) {
      final quads = <_Quad>[];
      Vector3 toWorld(Offset q) {
        if (s.isFloor) return _w(q, 0);
        final i = s.wallIndex!;
        final a = p.wallStart(i), b = p.wallEnd(i);
        final dir = (b - a) / p.wallLength(i);
        return _w(a + dir * q.dx, q.dy);
      }

      // Mirrored walls run right to left from inside; flip u so photos read correctly.
      Offset uvOf(Offset q) => s.isFloor ? q - s.origin : Offset(s.mirrored ? -q.dx : q.dx, -q.dy);

      void cell(Rect r, int depth) {
        final samples = <String?>[];
        for (var a = 0; a < 3; a++) {
          for (var b = 0; b < 3; b++) {
            samples.add(s.classify(Offset(r.left + r.width * (0.02 + 0.48 * a), r.top + r.height * (0.02 + 0.48 * b))));
          }
        }
        final uniform = samples.every((k) => k == samples.first);
        if (!uniform && r.width > 2.5 && depth < 8) {
          final c = r.center;
          cell(Rect.fromLTRB(r.left, r.top, c.dx, c.dy), depth + 1);
          cell(Rect.fromLTRB(c.dx, r.top, r.right, c.dy), depth + 1);
          cell(Rect.fromLTRB(r.left, c.dy, c.dx, r.bottom), depth + 1);
          cell(Rect.fromLTRB(c.dx, c.dy, r.right, r.bottom), depth + 1);
          return;
        }
        final key = uniform ? samples.first : samples[4];
        if (key == null) return;
        final pts = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
        quads.add(_Quad(pts.map(toWorld).toList(), pts.map(uvOf).toList(), key));
      }

      final b = s.bounds;
      const step = 15.0;
      for (var x = b.left; x < b.right - 0.01; x += step) {
        for (var y = b.top; y < b.bottom - 0.01; y += step) {
          cell(Rect.fromLTRB(x, y, math.min(x + step, b.right), math.min(y + step, b.bottom)), 0);
        }
      }
      if (!s.isFloor) {
        for (final o in p.walls[s.wallIndex!].openings) {
          final r = o.rect.intersect(s.bounds);
          if (r.width <= 0 || r.height <= 0) continue;
          final pts = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
          quads.add(
            _Quad(
              pts.map(toWorld).toList(),
              pts.map(uvOf).toList(),
              o.type == OpeningType.door ? _doorKey : _windowKey,
            ),
          );
        }
      }
      if (s.isFloor) {
        final c = centroid(p.points);
        surfaces.add(_SurfaceMesh(quads, _w(c, 0), 0.95, isFloor: true));
        final top = p.walls.take(p.edgeCount).fold<double>(0, (m, w) => math.max(m, w.height));
        final ceiling = [
          for (final q in quads)
            if (q.key != _doorKey) _Quad([for (final v in q.pos) Vector3(v.x, top, v.z)], q.uv, _ceilingKey),
        ];
        surfaces.add(_SurfaceMesh(ceiling, _w(c, top), 1, isFloor: true, isCeiling: true));
      } else {
        final i = s.wallIndex!;
        final a = p.wallStart(i), bb = p.wallEnd(i);
        final n = inwardNormal(p.points, i);
        final shade = 0.72 + 0.28 * (dot(n, light).abs());
        surfaces.add(_SurfaceMesh(quads, _w((a + bb) / 2, p.walls[i].height / 2), shade, wallA: a, wallNormal: n));
      }
    }

    final faces = <_Face>[];
    for (final f in p.fixtures) {
      for (final bx in fixtureBoxes(f)) {
        Vector3 v(double x, double y, double z) => _w(f.toPlan(x, y), z);
        final c = [
          v(bx.x0, bx.y0, bx.z0),
          v(bx.x1, bx.y0, bx.z0),
          v(bx.x1, bx.y1, bx.z0),
          v(bx.x0, bx.y1, bx.z0),
          v(bx.x0, bx.y0, bx.z1),
          v(bx.x1, bx.y0, bx.z1),
          v(bx.x1, bx.y1, bx.z1),
          v(bx.x0, bx.y1, bx.z1),
        ];
        final center = c.fold(Vector3.zero(), (a, b) => a + b) / 8;
        for (final idx in const [
          [0, 1, 2, 3],
          [4, 5, 6, 7],
          [0, 1, 5, 4],
          [1, 2, 6, 5],
          [2, 3, 7, 6],
          [3, 0, 4, 7],
        ]) {
          final pts = idx.map((k) => c[k]).toList();
          var n = (pts[1] - pts[0]).cross(pts[2] - pts[0]);
          if (n.length2 == 0) n = (pts[2] - pts[1]).cross(pts[3] - pts[1]);
          if (n.length2 == 0) continue;
          n.normalize();
          final fc = pts.fold(Vector3.zero(), (a, b) => a + b) / 4;
          if (n.dot(fc - center) < 0) n = -n;
          faces.add(_Face(pts, bx.color, n));
        }
      }
    }
    return _RoomMesh(surfaces, faces);
  }
}

class _Camera {
  Vector3 eye;
  double yaw; // 0 looks along +z
  double pitch;
  _Camera(this.eye, this.yaw, this.pitch);

  Vector3 get forward => Vector3(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch));

  Vector3 toCam(Vector3 p) {
    final d = p - eye;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final x1 = d.x * cy - d.z * sy;
    final z1 = d.x * sy + d.z * cy;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y2 = d.y * cp - z1 * sp;
    final z2 = d.y * sp + z1 * cp;
    return Vector3(x1, y2, z2);
  }
}

/// Walk-around 3D view of the room with tiles, doors and fixtures.
class Room3DView extends StatefulWidget {
  final Project project;
  final int revision;
  const Room3DView({super.key, required this.project, required this.revision});

  @override
  State<Room3DView> createState() => _Room3DViewState();
}

class _Room3DViewState extends State<Room3DView> {
  _RoomMesh? _mesh;
  int _meshRev = -1;
  late _Camera _cam;
  bool _inside = true;
  double _orbitDist = 600;
  double _startDist = 600;
  Timer? _repeat;
  Offset _lastFocal = Offset.zero;
  int _pointers = 0;

  Project get p => widget.project;

  @override
  void initState() {
    super.initState();
    _resetCamera();
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  Offset get _roomCenter => p.points.length >= 3 ? centroid(p.points) : Offset.zero;

  void _resetCamera() {
    final c = _roomCenter;
    // Look towards the longest wall from the room centre.
    var yaw = 0.0;
    if (p.closed && p.points.length >= 3) {
      var best = -1.0;
      for (var i = 0; i < p.edgeCount; i++) {
        if (p.wallLength(i) > best) {
          best = p.wallLength(i);
          final mid = (p.wallStart(i) + p.wallEnd(i)) / 2;
          final d = mid - c;
          yaw = math.atan2(d.dx, -d.dy);
        }
      }
      final b = boundsOf(p.points);
      _orbitDist = math.max(b.width, b.height) * 1.15 + 120;
    }
    if (_inside) {
      _cam = _Camera(_w(_startPoint(yaw), 160), yaw, -0.12);
      if (_lookAt != null) {
        final d = _lookAt! - Offset(_cam.eye.x, -_cam.eye.z);
        _cam.yaw = math.atan2(d.dx, -d.dy);
      }
    } else {
      _cam = _Camera(Vector3.zero(), yaw + 0.6, -0.75);
      _placeOrbit();
    }
  }

  Offset? _lookAt;

  /// A free spot far from the wall we look at, clear of walls and fixtures.
  Offset _startPoint(double yaw) {
    final c = _roomCenter;
    _lookAt = null;
    if (p.points.length < 3) return c;
    var target = c;
    var best = -1.0;
    for (var i = 0; i < p.edgeCount; i++) {
      if (p.wallLength(i) > best) {
        best = p.wallLength(i);
        target = (p.wallStart(i) + p.wallEnd(i)) / 2;
      }
    }
    final b = boundsOf(p.points);
    final step = math.max(5.0, math.max(b.width, b.height) / 40);
    Offset? pick;
    var pickScore = -1.0;
    for (var x = b.left; x <= b.right; x += step) {
      for (var y = b.top; y <= b.bottom; y += step) {
        final q = Offset(x, y);
        if (!pointInPolygon(q, p.points)) continue;
        var clear = double.infinity;
        for (var i = 0; i < p.edgeCount; i++) {
          clear = math.min(clear, distToSegment(q, p.wallStart(i), p.wallEnd(i)));
        }
        if (clear < 25) continue;
        if (p.fixtures.any((f) => f.elevation < 150 && f.contains(q))) continue;
        final near = p.fixtures
            .where((f) => f.elevation < 150)
            .fold<double>(
              double.infinity,
              (m, f) => math.min(m, (f.pos - q).distance - math.max(f.width, f.depth) / 2),
            );
        if (near < 20) continue;
        final score = (q - target).distance;
        if (score > pickScore) {
          pickScore = score;
          pick = q;
        }
      }
    }
    if (pick == null) return c;
    _lookAt = target;
    return pick;
  }

  void _placeOrbit() {
    final target = _w(_roomCenter, 60);
    _cam.eye = target - _cam.forward * _orbitDist;
  }

  void _move(double forward, double strafe) {
    if (!_inside) {
      setState(() {
        _orbitDist = (_orbitDist - forward * 3).clamp(150.0, 3000.0);
        _cam.yaw += strafe * 0.01;
        _placeOrbit();
      });
      return;
    }
    final f = Offset(math.sin(_cam.yaw), math.cos(_cam.yaw));
    final r = Offset(math.cos(_cam.yaw), -math.sin(_cam.yaw));
    final d = f * forward + r * strafe;
    final next = Vector3(_cam.eye.x + d.dx, _cam.eye.y, _cam.eye.z + d.dy);
    final plan = Offset(next.x, -next.z);
    if (p.points.length < 3 || pointInPolygon(plan, p.points)) {
      setState(() => _cam.eye = next);
    }
  }

  void _startRepeat(double forward, double strafe) {
    _move(forward, strafe);
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 30), (_) => _move(forward * 0.4, strafe * 0.4));
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!p.closed || p.points.length < 3) {
      return Center(child: Text(tr('Finish the room plan to see it in 3D.')));
    }
    if (_mesh == null || _meshRev != widget.revision) {
      _mesh = _RoomMesh.build(p);
      _meshRev = widget.revision;
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _move(e.scrollDelta.dy > 0 ? -20 : 20, 0);
            },
            child: GestureDetector(
              onScaleStart: (d) {
                _pointers = d.pointerCount;
                _lastFocal = d.localFocalPoint;
                _startDist = _orbitDist;
              },
              onScaleUpdate: (d) {
                final delta = d.localFocalPoint - _lastFocal;
                _lastFocal = d.localFocalPoint;
                if (d.pointerCount != _pointers) {
                  _pointers = d.pointerCount;
                  _startDist = _orbitDist / d.scale;
                  return;
                }
                setState(() {
                  if (d.pointerCount >= 2) {
                    if (_inside) {
                      _move((d.scale - 1) * 6, 0);
                    } else {
                      _orbitDist = (_startDist / d.scale).clamp(150.0, 3000.0);
                      _placeOrbit();
                    }
                    return;
                  }
                  _cam.yaw -= delta.dx * 0.006 * (_inside ? 1 : -1);
                  _cam.pitch = (_cam.pitch - delta.dy * 0.004 * (_inside ? 1 : -1)).clamp(
                    _inside ? -1.3 : -1.5,
                    _inside ? 1.3 : -0.05,
                  );
                  if (!_inside) _placeOrbit();
                });
              },
              child: CustomPaint(painter: _RoomPainter(_mesh!, _cam, store)),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(tr('Inside')), icon: Icon(Icons.accessibility_new)),
              ButtonSegment(value: false, label: Text(tr('Overview')), icon: Icon(Icons.view_in_ar)),
            ],
            selected: {_inside},
            style: const ButtonStyle(backgroundColor: WidgetStatePropertyAll(Color(0xEEFFFFFF))),
            onSelectionChanged: (s) => setState(() {
              _inside = s.first;
              _resetCamera();
            }),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _Pad(onStart: _startRepeat, onStop: _stopRepeat),
        ),
        Positioned(
          left: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(12)),
            child: Text(
              _inside ? tr('Drag to look around · pinch to walk') : tr('Drag to orbit · pinch to zoom'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

class _Pad extends StatelessWidget {
  final void Function(double forward, double strafe) onStart;
  final VoidCallback onStop;
  const _Pad({required this.onStart, required this.onStop});

  Widget _btn(IconData icon, double f, double s) => GestureDetector(
    onTapDown: (_) => onStart(f, s),
    onTapUp: (_) => onStop(),
    onTapCancel: onStop,
    child: Container(
      width: 48,
      height: 48,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: const Color(0xDDFFFFFF), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.keyboard_arrow_up, 15, 0),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _btn(Icons.keyboard_arrow_left, 0, -15),
            const SizedBox(width: 52),
            _btn(Icons.keyboard_arrow_right, 0, 15),
          ],
        ),
        _btn(Icons.keyboard_arrow_down, -15, 0),
      ],
    );
  }
}

class _Buf {
  final pos = <double>[];
  final tex = <double>[];
  final col = <int>[];
}

class _RoomPainter extends CustomPainter {
  final _RoomMesh mesh;
  final _Camera cam;
  final AppStore store;
  _RoomPainter(this.mesh, this.cam, this.store);

  static const _near = 2.0;

  /// Clips a polygon (camera space) against the near plane, carrying uvs.
  (List<Vector3>, List<Offset>) _clip(List<Vector3> v, List<Offset> uv) {
    final ov = <Vector3>[], ou = <Offset>[];
    for (var i = 0; i < v.length; i++) {
      final a = v[i], b = v[(i + 1) % v.length];
      final ua = uv[i], ub = uv[(i + 1) % v.length];
      final ina = a.z > _near, inb = b.z > _near;
      if (ina) {
        ov.add(a);
        ou.add(ua);
      }
      if (ina != inb) {
        final t = (_near - a.z) / (b.z - a.z);
        ov.add(a + (b - a) * t);
        ou.add(ua + (ub - ua) * t);
      }
    }
    return (ov, ou);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
          const Color(0xFFDDE4EA),
          const Color(0xFFF5F5F2),
        ]),
    );
    final cx = size.width / 2, cy = size.height / 2;
    // 90° across the narrow side of the screen, like a wide phone camera.
    final focal = math.min(size.width, size.height) / 2 / math.tan(45 * math.pi / 180);
    Offset proj(Vector3 c) => Offset(cx + focal * c.x / c.z, cy - focal * c.y / c.z);

    final eyePlan = Offset(cam.eye.x, -cam.eye.z);
    final visible = <_SurfaceMesh>[];
    for (final s in mesh.surfaces) {
      if (s.wallNormal != null && dot(eyePlan - s.wallA!, s.wallNormal!) <= 0) continue;
      if (s.isCeiling && cam.eye.y >= s.center.y) continue;
      visible.add(s);
    }
    visible.sort((a, b) {
      if (a.isFloor != b.isFloor) return a.isFloor ? -1 : 1;
      return (b.center - cam.eye).length.compareTo((a.center - cam.eye).length);
    });

    for (final s in visible) {
      final bufs = <String, _Buf>{};
      final shade = (s.shade * 255).round().clamp(0, 255);
      for (final q in s.quads) {
        final cv = q.pos.map(cam.toCam).toList();
        if (cv.every((v) => v.z <= _near)) continue;
        final (v, uv) = _clip(cv, q.uv);
        if (v.length < 3) continue;
        final b = bufs.putIfAbsent(q.key, () => _Buf());
        final pts = v.map(proj).toList();
        final tex = store.texture(q.key);
        final ppc = tex?.ppc ?? 1;
        final tile = store.tileOfKey(q.key);
        final base = q.key == _ceilingKey
            ? const Color(0xFFFAFAF8)
            : q.key == _doorKey
            ? const Color(0xFF8B6447)
            : q.key == _windowKey
            ? const Color(0xFFBFE3F2)
            : q.key == plainKey || tile == null
            ? (s.isFloor ? const Color(0xFFD8D3CA) : const Color(0xFFF1ECE3))
            : (tex == null ? tile.color : Colors.white);
        final r = (base.r * shade).round(), g = (base.g * shade).round(), bl = (base.b * shade).round();
        final col = (0xFF << 24) | (r << 16) | (g << 8) | bl;
        for (var k = 1; k < pts.length - 1; k++) {
          for (final j in [0, k, k + 1]) {
            b.pos
              ..add(pts[j].dx)
              ..add(pts[j].dy);
            b.tex
              ..add(uv[j].dx * ppc)
              ..add(uv[j].dy * ppc);
            b.col.add(col);
          }
        }
      }
      bufs.forEach((key, b) {
        if (b.pos.isEmpty) return;
        final tex = store.texture(key);
        final vertices = ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.fromList(b.pos),
          textureCoordinates: tex == null ? null : Float32List.fromList(b.tex),
          colors: Int32List.fromList(b.col),
        );
        final paint = Paint()..color = Colors.white;
        if (tex != null) {
          paint.shader = ImageShader(tex.image, TileMode.repeated, TileMode.repeated, Float64List.fromList(_identity));
          paint.filterQuality = FilterQuality.low;
        }
        canvas.drawVertices(vertices, BlendMode.modulate, paint);
      });
    }

    // Fixtures, far to near.
    final faces = <(double, List<Offset>, int)>[];
    final light = Vector3(0.4, 0.8, -0.45)..normalize();
    for (final f in mesh.faces) {
      final fc = f.pos.fold(Vector3.zero(), (a, b) => a + b) / 4;
      if (f.color.a > 0.9 && f.normal.dot(cam.eye - fc) <= 0) continue;
      final cv = f.pos.map(cam.toCam).toList();
      if (cv.every((v) => v.z <= _near)) continue;
      final (v, _) = _clip(cv, const [Offset.zero, Offset.zero, Offset.zero, Offset.zero]);
      if (v.length < 3) continue;
      final depth = cam.toCam(fc).z;
      final k = 0.62 + 0.38 * math.max(0.0, f.normal.dot(light));
      final c = f.color;
      final col =
          ((c.a * 255).round() << 24) |
          ((c.r * 255 * k).round().clamp(0, 255) << 16) |
          ((c.g * 255 * k).round().clamp(0, 255) << 8) |
          (c.b * 255 * k).round().clamp(0, 255);
      faces.add((depth, v.map(proj).toList(), col));
    }
    faces.sort((a, b) => b.$1.compareTo(a.$1));
    final pos = <double>[];
    final col = <int>[];
    for (final (_, pts, c) in faces) {
      for (var k = 1; k < pts.length - 1; k++) {
        for (final j in [0, k, k + 1]) {
          pos
            ..add(pts[j].dx)
            ..add(pts[j].dy);
          col.add(c);
        }
      }
    }
    if (pos.isNotEmpty) {
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos), colors: Int32List.fromList(col)),
        BlendMode.modulate,
        Paint()..color = Colors.white,
      );
    }
  }

  static const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

  @override
  bool shouldRepaint(covariant _RoomPainter old) => true;
}
