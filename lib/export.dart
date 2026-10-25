import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';

import 'i18n.dart';
import 'models.dart';
import 'store.dart';
import 'surfaces.dart';
import 'widgets/common.dart';
import 'widgets/surface_paint.dart';
import 'widgets/view3d.dart';

/// One picture for the customer, named date-tiles-details.jpg.
class ExportFile {
  final String name;
  final Uint8List jpg;
  ExportFile(this.name, this.jpg);
}

const _ink = Color(0xFF1B2631);
const _cutColor = Color(0xFFE65100);
const _doorColor = Color(0xFFD7CCC8);
const _windowColor = Color(0xFFB3E5FC);

String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lower-case file-name part with spaces and unsafe characters as dashes.
String _slug(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'[\s\\/:*?"<>|#%&{}$!@+=`]+'), '-').replaceAll(RegExp(r'-+'), '-');

/// Tile code as written (e.g. W-3060), else its name, safe for file names.
String _tileId(Tile t) => (t.code.isNotEmpty ? t.code : (t.name.isNotEmpty ? t.name : t.id.substring(0, 6)))
    .trim()
    .replaceAll(RegExp(r'[\s\\/:*?"<>|#%&{}$!@+=`]+'), '-');

String _fileName(DateTime date, Iterable<Tile> tiles, List<String> details) {
  final ids = {for (final t in tiles) _tileId(t)}.join('+');
  final parts = [_date(date), if (ids.isNotEmpty) ids, ...details.map(_slug)].where((e) => e.isNotEmpty);
  return '${parts.join('-')}.jpg';
}

Future<Uint8List> _jpg(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = image.width, h = image.height;
  return compute(_encodeJpg, (data!.buffer.asUint8List(), w, h));
}

Uint8List _encodeJpg((Uint8List, int, int) a) {
  final im = img.Image.fromBytes(width: a.$2, height: a.$3, bytes: a.$1.buffer, numChannels: 4);
  return img.encodeJpg(im, quality: 90);
}

void _text(
  Canvas c,
  String s,
  Offset at, {
  double size = 22,
  Color color = _ink,
  FontWeight weight = FontWeight.w500,
  TextAlign align = TextAlign.left,
  double? maxWidth,
  bool center = false,
  Color? box,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontFamily: 'Roboto', fontSize: size, color: color, fontWeight: weight, height: 1.15),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  final o = center ? at - Offset(tp.width / 2, tp.height / 2) : at;
  if (box != null) {
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(o.dx - 3, o.dy - 1, tp.width + 6, tp.height + 2), const Radius.circular(3)),
      Paint()..color = box,
    );
  }
  tp.paint(c, o);
}

String _alignName(TileAlign a) => switch (a) {
  TileAlign.left => tr('from the left'),
  TileAlign.right => tr('from the right'),
  TileAlign.center => tr('centred'),
};

/// Draws one surface as seen from inside the room. The [technical] version
/// adds contrast joint lines, tile numbers, cut sizes, dimensions and a legend;
/// otherwise only the tiles, doors and windows are drawn.
Future<ui.Image> renderSurface(Project p, AppStore store, SurfaceModel s, {required bool technical}) async {
  final tiles = store.tileMap;
  final layers = <LayerLayout>[for (var l = -1; l < s.tiling.regions.length; l++) ?s.layout(l, tiles)];
  for (final l in layers) {
    await store.loadTexture(l.key);
  }
  final b = s.bounds;
  const width = 2400.0, margin = 90.0;
  final k = math.min((width - 2 * margin) / math.max(b.width, 1), 2600 / math.max(b.height, 1));
  final drawW = b.width * k, drawH = b.height * k;
  final isWall = !s.isFloor;
  final flipX = s.mirrored;

  final cells = <LayerLayout, List<TileCell>>{for (final l in layers) l: technical ? layoutCells(s, l, fine: 14) : []};
  final legendLines = technical ? layers.length + 2 : 0;
  final top = technical ? 150.0 + legendLines * 40 : margin;
  final height = top + drawH + (technical ? 130 : margin);
  final left = (width - drawW) / 2;

  // Surface centimetres to picture pixels, inside view.
  Offset px(Offset q) =>
      Offset(left + (flipX ? b.right - q.dx : q.dx - b.left) * k, top + (isWall ? b.bottom - q.dy : q.dy - b.top) * k);
  Rect pxRect(Rect r) => Rect.fromPoints(px(r.topLeft), px(r.bottomRight));

  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);

  c.save();
  c.translate(px(Offset(flipX ? b.right : b.left, 0)).dx, px(Offset(0, isWall ? b.bottom : b.top)).dy);
  c.scale(k * (flipX ? -1 : 1), k * (isWall ? -1 : 1));
  c.translate(-(flipX ? b.right : b.left), -(isWall ? b.bottom : b.top));
  paintSurface(c, store, s, plain: const Color(0xFFF2EFEA), flipY: isWall, flipX: flipX);
  if (technical) {
    // Soften the photos so joints and numbers stand out.
    c.drawPath(Path()..addPolygon(s.base, true), Paint()..color = const Color(0x8CFFFFFF));
    final joint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 / k
      ..color = _ink;
    final cutFill = Paint()..color = _cutColor.withValues(alpha: 0.16);
    final cutLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 / k
      ..color = _cutColor;
    for (final l in layers) {
      var area = Path()..addPolygon(s.polygonOf(l.layer), true);
      for (var i = l.layer + 1; i < s.tiling.regions.length; i++) {
        if (s.tiling.regions[i].points.length < 3) continue;
        area = Path.combine(PathOperation.difference, area, Path()..addPolygon(s.tiling.regions[i].points, true));
      }
      c.save();
      c.clipPath(area);
      for (final cell in cells[l]!) {
        if (!cell.whole) {
          c.drawRect(cell.piece, cutFill);
          c.drawRect(cell.piece, cutLine);
        }
        c.drawRect(cell.rect, joint);
      }
      c.restore();
    }
    c.drawPath(
      Path()..addPolygon(s.base, true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 / k
        ..color = _ink,
    );
  }
  c.restore();

  // Doors and windows on top.
  if (isWall) {
    for (final o in p.walls[s.wallIndex!].openings) {
      final r = pxRect(o.rect.intersect(b));
      if (r.isEmpty) continue;
      c.drawRect(r, Paint()..color = o.type == OpeningType.door ? _doorColor : _windowColor);
      c.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF5D4037),
      );
      if (technical) {
        _text(
          c,
          '${o.type == OpeningType.door ? tr('Door') : tr('Window')}\n${fmtNum(o.width)}×${fmtNum(o.height)}',
          r.center,
          size: 24,
          center: true,
          align: TextAlign.center,
          box: const Color(0xD9FFFFFF),
        );
      }
    }
  }

  if (technical) {
    final many = layers.length > 1;
    for (final (li, l) in layers.indexed) {
      final prefix = many ? String.fromCharCode(65 + li) : '';
      for (final (i, cell) in cells[l]!.indexed) {
        final r = pxRect(cell.piece);
        final fs = (math.min(r.width, r.height) * 0.24).clamp(9.0, 26.0);
        if (math.min(r.width, r.height) < 16) continue;
        final label = cell.whole
            ? '$prefix${i + 1}'
            : '$prefix${i + 1}\n${fmtNum((cell.piece.width * 10).roundToDouble() / 10)}×${fmtNum((cell.piece.height * 10).roundToDouble() / 10)}';
        _text(
          c,
          label,
          px(cell.center),
          size: fs,
          center: true,
          align: TextAlign.center,
          weight: cell.whole ? FontWeight.w600 : FontWeight.w700,
          color: cell.whole ? _ink : _cutColor,
        );
      }
    }

    // Header.
    final title = isWall ? '${p.name} · ${s.name} · ${tr('inside view')}' : '${p.name} · ${s.name}';
    _text(c, title, const Offset(margin, 40), size: 40, weight: FontWeight.w700);
    _text(
      c,
      '${fmtNum((b.width * 10).roundToDouble() / 10)} × ${fmtNum((b.height * 10).roundToDouble() / 10)} ${tr('cm')} · ${_date(DateTime.now())}',
      const Offset(margin, 92),
      size: 26,
      color: const Color(0xFF546E7A),
    );
    var y = 150.0;
    for (final (li, l) in layers.indexed) {
      final n = cells[l]!.length, whole = cells[l]!.where((e) => e.whole).length;
      c.drawRect(Rect.fromLTWH(margin, y + 2, 28, 28), Paint()..color = l.tile.color);
      c.drawRect(
        Rect.fromLTWH(margin, y + 2, 28, 28),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _ink,
      );
      final lay = layoutOfKey(l.key);
      _text(
        c,
        '${layers.length > 1 ? '${String.fromCharCode(65 + li)}: ' : ''}${l.tile.label} · '
        '${tr('laid')} ${fmtNum(l.tw)}×${fmtNum(l.th)} · ${tr('gap')} ${fmtNum(lay.gapMm)} ${tr('mm')} · ${_alignName(l.align)} · '
        '${tr('{n} pcs', {'n': n})} (${tr('{full} whole + {cut} cut', {'full': whole, 'cut': n - whole})})',
        Offset(margin + 42, y),
        size: 24,
        maxWidth: width - 2 * margin - 42,
      );
      y += 40;
    }
    c.drawRect(Rect.fromLTWH(margin, y + 2, 28, 28), Paint()..color = _cutColor.withValues(alpha: 0.3));
    _text(
      c,
      tr('Cut tile: number, then the piece size width × height in cm as seen in this view'),
      Offset(margin + 42, y),
      size: 22,
      color: _cutColor,
    );

    // Overall dimensions.
    final bl = Offset(left, top + drawH), br = Offset(left + drawW, top + drawH);
    final dim = Paint()
      ..color = _ink
      ..strokeWidth = 2;
    c.drawLine(bl + const Offset(0, 30), br + const Offset(0, 30), dim);
    c.drawLine(bl + const Offset(0, 18), bl + const Offset(0, 42), dim);
    c.drawLine(br + const Offset(0, 18), br + const Offset(0, 42), dim);
    _text(
      c,
      '${fmtNum((b.width * 10).roundToDouble() / 10)} ${tr('cm')}',
      Offset(left + drawW / 2, top + drawH + 30),
      size: 26,
      center: true,
      weight: FontWeight.w700,
      box: Colors.white,
    );
    c.drawLine(Offset(left - 30, top), Offset(left - 30, top + drawH), dim);
    c.save();
    c.translate(left - 30, top + drawH / 2);
    c.rotate(-math.pi / 2);
    _text(
      c,
      '${fmtNum((b.height * 10).roundToDouble() / 10)} ${tr('cm')}',
      Offset.zero,
      size: 26,
      center: true,
      weight: FontWeight.w700,
      box: Colors.white,
    );
    c.restore();
  }

  return rec.endRecording().toImage(width.round(), height.round());
}

/// Builds the chosen pictures for [p].
Future<List<ExportFile>> buildExport(
  Project p,
  AppStore store, {
  required bool layouts,
  required bool clean,
  required bool views3d,
  void Function(String step)? progress,
}) async {
  final now = DateTime.now();
  final tiles = store.tileMap;
  final out = <ExportFile>[];
  for (final s in SurfaceModel.all(p)) {
    final used = [for (var l = -1; l < s.tiling.regions.length; l++) ?s.layout(l, tiles)?.tile];
    if (used.isEmpty) continue;
    final surface = s.isFloor ? 'floor' : 'wall-${s.wallIndex! + 1}';
    if (layouts) {
      progress?.call(s.name);
      final im = await renderSurface(p, store, s, technical: true);
      out.add(ExportFile(_fileName(now, used, [p.name, surface, 'layout']), await _jpg(im)));
    }
    if (clean) {
      progress?.call(s.name);
      final im = await renderSurface(p, store, s, technical: false);
      out.add(ExportFile(_fileName(now, used, [p.name, surface, 'view']), await _jpg(im)));
    }
  }
  if (views3d) {
    progress?.call(tr('3D'));
    final roomTiles = store.countsFor(p).values.map((c) => c.tile);
    for (final (name, im) in await render3DViews(p, store)) {
      out.add(ExportFile(_fileName(now, roomTiles, [p.name, '3d', name]), await _jpg(im)));
    }
  }
  return out;
}

/// Lets the user pick what to export, then shares the pictures.
Future<void> showExportSheet(BuildContext context, Project p) {
  var layouts = true, clean = true, views3d = true;
  String? busy;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final store = AppScope.of(c);
        Future<void> run() async {
          setState(() => busy = tr('Preparing…'));
          try {
            final files = await buildExport(
              p,
              store,
              layouts: layouts,
              clean: clean,
              views3d: views3d,
              progress: (s) => setState(() => busy = s),
            );
            if (files.isEmpty) return;
            setState(() => busy = tr('Sharing…'));
            await SharePlus.instance.share(
              ShareParams(
                files: [for (final f in files) XFile.fromData(f.jpg, mimeType: 'image/jpeg', name: f.name)],
                fileNameOverrides: [for (final f in files) f.name],
                subject: p.name,
              ),
            );
            if (c.mounted) Navigator.pop(c);
          } catch (e) {
            if (c.mounted) {
              ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(tr('Export failed: {e}', {'e': e}))));
            }
          } finally {
            if (c.mounted) setState(() => busy = null);
          }
        }

        final theme = Theme.of(c);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Export for customer'), style: theme.textTheme.titleLarge),
                gap(4),
                Text(
                  tr('JPG pictures named date-tile-details, for example {e}', {
                    'e': _fileName(DateTime.now(), store.countsFor(p).values.map((e) => e.tile).take(1), [
                      p.name,
                      'wall-1',
                      'layout',
                    ]),
                  }),
                  style: theme.textTheme.bodySmall,
                ),
                gap(8),
                CheckboxListTile(
                  value: layouts,
                  onChanged: busy != null ? null : (v) => setState(() => layouts = v!),
                  title: Text(tr('Tile layouts')),
                  subtitle: Text(tr('Joint lines, tile numbers and cut sizes for every wall and the floor')),
                ),
                CheckboxListTile(
                  value: clean,
                  onChanged: busy != null ? null : (v) => setState(() => clean = v!),
                  title: Text(tr('Clean views')),
                  subtitle: Text(tr('Only the tiles, no extra information')),
                ),
                CheckboxListTile(
                  value: views3d,
                  onChanged: busy != null ? null : (v) => setState(() => views3d = v!),
                  title: Text(tr('3D pictures')),
                  subtitle: Text(tr('Views from inside the room and from above')),
                ),
                gap(8),
                FilledButton.icon(
                  onPressed: busy != null || !(layouts || clean || views3d) ? null : run,
                  icon: busy != null
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share),
                  label: Text(busy ?? tr('Create and share')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
