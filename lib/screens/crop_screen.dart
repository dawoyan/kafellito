import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../i18n.dart';

/// Lets the user frame one tile in a photo. Returns PNG bytes of the crop.
class CropScreen extends StatefulWidget {
  final Uint8List bytes;

  /// Width / height of the tile, used to lock the crop shape.
  final double? aspect;
  const CropScreen({super.key, required this.bytes, this.aspect});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  ui.Image? _image;
  // Crop rectangle in image pixels.
  Rect _crop = Rect.zero;
  bool _lock = true;
  int? _handle; // 0..3 corners, 4 = move
  Offset _last = Offset.zero;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final img = (await codec.getNextFrame()).image;
    final w = img.width.toDouble(), h = img.height.toDouble();
    var cw = w * 0.8, ch = h * 0.8;
    final a = widget.aspect;
    if (a != null && a > 0) {
      if (cw / ch > a) {
        cw = ch * a;
      } else {
        ch = cw / a;
      }
    }
    setState(() {
      _image = img;
      _crop = Rect.fromCenter(center: Offset(w / 2, h / 2), width: cw, height: ch);
    });
  }

  ({double scale, Offset offset}) _fit(Size size) {
    final img = _image!;
    final s = math.min(size.width / img.width, size.height / img.height);
    final off = Offset((size.width - img.width * s) / 2, (size.height - img.height * s) / 2);
    return (scale: s, offset: off);
  }

  List<Offset> _corners(Rect r) => [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];

  void _onStart(Offset local, Size size) {
    final f = _fit(size);
    final p = (local - f.offset) / f.scale;
    final tol = 32 / f.scale;
    final cs = _corners(_crop);
    _handle = null;
    for (var i = 0; i < 4; i++) {
      if ((cs[i] - p).distance < tol) _handle = i;
    }
    if (_handle == null && _crop.contains(p)) _handle = 4;
    _last = p;
  }

  void _onUpdate(Offset local, Size size) {
    if (_handle == null) return;
    final f = _fit(size);
    final p = (local - f.offset) / f.scale;
    final img = _image!;
    final bounds = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    setState(() {
      if (_handle == 4) {
        var r = _crop.shift(p - _last);
        final dx = r.left < 0 ? -r.left : (r.right > bounds.right ? bounds.right - r.right : 0.0);
        final dy = r.top < 0 ? -r.top : (r.bottom > bounds.bottom ? bounds.bottom - r.bottom : 0.0);
        _crop = r.shift(Offset(dx, dy));
      } else {
        final q = Offset(p.dx.clamp(0, bounds.right), p.dy.clamp(0, bounds.bottom));
        final opposite = _corners(_crop)[(_handle! + 2) % 4];
        var w = (q.dx - opposite.dx).abs(), h = (q.dy - opposite.dy).abs();
        final a = widget.aspect;
        if (_lock && a != null && a > 0) {
          if (w / math.max(h, 1) > a) {
            h = w / a;
          } else {
            w = h * a;
          }
        }
        w = math.max(w, 20);
        h = math.max(h, 20);
        final sx = q.dx < opposite.dx ? -1 : 1, sy = q.dy < opposite.dy ? -1 : 1;
        final r = Rect.fromPoints(opposite, opposite + Offset(sx * w, sy * h));
        _crop = r.intersect(bounds);
      }
      _last = p;
    });
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    final img = _image!;
    final maxSide = 320.0;
    final s = math.min(1.0, maxSide / math.max(_crop.width, _crop.height));
    final w = math.max(1, (_crop.width * s).round()), h = math.max(1, (_crop.height * s).round());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImageRect(
      img,
      _crop,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final out = await rec.endRecording().toImage(w, h);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.pop(context, data!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(tr('Frame one tile')),
        actions: [
          if (widget.aspect != null)
            IconButton(
              tooltip: _lock ? tr('Unlock shape') : tr('Lock to tile size'),
              icon: Icon(_lock ? Icons.lock : Icons.lock_open),
              onPressed: () => setState(() => _lock = !_lock),
            ),
          TextButton(onPressed: _image == null || _busy ? null : _done, child: Text(tr('Use'))),
        ],
      ),
      body: _image == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, cons) {
                final size = cons.biggest;
                return GestureDetector(
                  onPanStart: (d) => _onStart(d.localPosition, size),
                  onPanUpdate: (d) => _onUpdate(d.localPosition, size),
                  onPanEnd: (_) => _handle = null,
                  child: CustomPaint(size: size, painter: _CropPainter(_image!, _crop, _fit(size))),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            tr('Drag the corners so the box covers exactly one tile.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect crop;
  final ({double scale, Offset offset}) fit;
  _CropPainter(this.image, this.crop, this.fit);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(fit.offset.dx, fit.offset.dy);
    canvas.scale(fit.scale);
    final full = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImage(image, Offset.zero, Paint());
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRect(crop);
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));
    final s = 1 / fit.scale;
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..color = Colors.white,
    );
    for (final c in [crop.topLeft, crop.topRight, crop.bottomRight, crop.bottomLeft]) {
      canvas.drawCircle(c, 9 * s, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        9 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * s
          ..color = Colors.teal,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.crop != crop || old.image != image;
}
