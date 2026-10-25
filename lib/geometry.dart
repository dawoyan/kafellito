import 'dart:math' as math;
import 'dart:ui';

double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

double signedArea(List<Offset> pts) {
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    s += cross(pts[i], pts[(i + 1) % pts.length]);
  }
  return s / 2;
}

double polygonArea(List<Offset> pts) => signedArea(pts).abs();

bool pointInPolygon(Offset p, List<Offset> pts) {
  var inside = false;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final a = pts[i], b = pts[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

double distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = dot(ab, ab);
  if (len2 == 0) return (p - a).distance;
  final t = (dot(p - a, ab) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

Rect boundsOf(List<Offset> pts) {
  var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final p in pts) {
    l = math.min(l, p.dx);
    t = math.min(t, p.dy);
    r = math.max(r, p.dx);
    b = math.max(b, p.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

Offset centroid(List<Offset> pts) {
  final a = signedArea(pts);
  if (a.abs() < 1e-6) {
    var s = Offset.zero;
    for (final p in pts) {
      s += p;
    }
    return s / pts.length.toDouble();
  }
  var cx = 0.0, cy = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    final c = cross(p, q);
    cx += (p.dx + q.dx) * c;
    cy += (p.dy + q.dy) * c;
  }
  return Offset(cx / (6 * a), cy / (6 * a));
}

Offset rotateAround(Offset p, Offset c, double a) {
  final d = p - c;
  final cs = math.cos(a), sn = math.sin(a);
  return c + Offset(d.dx * cs - d.dy * sn, d.dx * sn + d.dy * cs);
}

double _norm(double a) {
  while (a < 0) {
    a += 2 * math.pi;
  }
  while (a >= 2 * math.pi) {
    a -= 2 * math.pi;
  }
  return a;
}

/// Interior angle at vertex [i], in degrees. For an open chain the angle is
/// measured on the side the chain is turning towards, falling back to the
/// smaller angle.
double interiorAngle(List<Offset> pts, int i, {bool closed = true}) {
  final n = pts.length;
  final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
  final a = math.atan2((prev - cur).dy, (prev - cur).dx);
  final b = math.atan2((next - cur).dy, (next - cur).dx);
  var ang = _norm(a - b); // angle from "next" to "prev"
  final orient = closed && n >= 3 ? signedArea(pts).sign : 0.0;
  if (orient < 0) {
    ang = 2 * math.pi - ang;
  } else if (orient == 0 && ang > math.pi) {
    ang = 2 * math.pi - ang;
  }
  return ang * 180 / math.pi;
}

/// Indices of the points that move when vertex [i] is changed, so that the
/// wall opposite the vertex stretches to absorb the change.
List<int> movingChain(int n, int i, bool closed) {
  if (!closed) return [for (var k = i + 1; k < n; k++) k];
  final k = math.max(1, (n - 1) ~/ 2);
  return [for (var j = 1; j <= k; j++) (i + j) % n];
}

/// Rotates the chain after vertex [i] so the interior angle becomes [deg].
List<Offset> setVertexAngle(List<Offset> pts, int i, double deg, {bool closed = true}) {
  final n = pts.length;
  final chain = movingChain(n, i, closed);
  final cur = interiorAngle(pts, i, closed: closed);
  final delta = (deg - cur) * math.pi / 180;
  List<Offset> attempt(double a) {
    final out = List.of(pts);
    for (final k in chain) {
      out[k] = rotateAround(pts[k], pts[i], a);
    }
    return out;
  }

  final a = attempt(delta), b = attempt(-delta);
  final ea = (interiorAngle(a, i, closed: closed) - deg).abs();
  final eb = (interiorAngle(b, i, closed: closed) - deg).abs();
  return ea <= eb ? a : b;
}

/// Sets the length of edge i (point i → i+1) by moving the chain after it.
List<Offset> setEdgeLength(List<Offset> pts, int i, double length, {bool closed = true}) {
  final n = pts.length;
  final a = pts[i], b = pts[(i + 1) % n];
  final dir = b - a;
  final len = dir.distance;
  if (len == 0) return pts;
  final delta = dir / len * (length - len);
  final out = List.of(pts);
  for (final k in movingChain(n, i, closed)) {
    out[k] = pts[k] + delta;
  }
  return out;
}

/// Unit normal of edge a→b pointing into the polygon.
Offset inwardNormal(List<Offset> pts, int i) {
  final a = pts[i], b = pts[(i + 1) % pts.length];
  final d = b - a;
  final len = d.distance;
  if (len == 0) return Offset.zero;
  var n = Offset(-d.dy / len, d.dx / len);
  final mid = (a + b) / 2;
  if (!pointInPolygon(mid + n * 0.5, pts)) n = -n;
  return n;
}

/// Clips [subject] against a convex [clip] polygon (Sutherland–Hodgman).
List<Offset> clipConvex(List<Offset> subject, List<Offset> clip) {
  var out = subject;
  final orient = signedArea(clip).sign;
  for (var i = 0; i < clip.length && out.isNotEmpty; i++) {
    final a = clip[i], b = clip[(i + 1) % clip.length];
    bool inside(Offset p) => cross(b - a, p - a) * orient >= 0;
    Offset inter(Offset p, Offset q) {
      final d1 = cross(b - a, p - a), d2 = cross(b - a, q - a);
      final t = d1 / (d1 - d2);
      return p + (q - p) * t;
    }

    final input = out;
    out = [];
    for (var j = 0; j < input.length; j++) {
      final p = input[j], q = input[(j + 1) % input.length];
      final pi = inside(p), qi = inside(q);
      if (pi) out.add(p);
      if (pi != qi) out.add(inter(p, q));
    }
  }
  return out;
}

Offset snapTo(Offset p, double step) =>
    Offset((p.dx / step).roundToDouble() * step, (p.dy / step).roundToDouble() * step);
