import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'common.dart';

Future<double?> showAngleDialog(BuildContext context, double current) {
  final ctrl = TextEditingController(text: '90')..selection = const TextSelection(baseOffset: 0, extentOffset: 2);
  void submit(BuildContext c) {
    final v = parseNum(ctrl.text);
    if (v != null && v > 0 && v < 360) Navigator.pop(c, v);
  }

  return showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Corner angle'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        NumberField(ctrl, 'Angle', suffix: '°', autofocus: true, onSubmitted: (_) => submit(c)),
        gap(8),
        Text('Now ${current.toStringAsFixed(1)}°. The opposite wall stretches to fit.',
            style: Theme.of(c).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => submit(c), child: const Text('Set')),
      ],
    ),
  );
}

class WallDialogResult {
  final double length;
  final double height;
  final String? tileId;
  final bool openWall;
  WallDialogResult(this.length, this.height, this.tileId, this.openWall);
}

Future<WallDialogResult?> showWallDialog(BuildContext context, int index, double length, Wall wall) {
  final len = numCtrl(length);
  final h = numCtrl(wall.height);
  String? tile = wall.tiling.tileId;
  return showDialog<WallDialogResult>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      WallDialogResult? result(bool open) {
        final l = parseNum(len.text), hh = parseNum(h.text);
        if (l == null || hh == null || l <= 0 || hh <= 0) return null;
        return WallDialogResult(l, hh, tile, open);
      }

      return AlertDialog(
        title: Text('Wall ${index + 1}'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: NumberField(len, 'Length', autofocus: true)),
              gap(),
              Expanded(child: NumberField(h, 'Height')),
            ]),
            gap(),
            TilePicker(value: tile, onChanged: (v) => setState(() => tile = v), label: 'Wall tile'),
            gap(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final r = result(true);
                  if (r != null) Navigator.pop(c, r);
                },
                icon: const Icon(Icons.open_in_full),
                label: Text(wall.tiling.regions.isEmpty && wall.openings.isEmpty
                    ? 'Open wall view'
                    : 'Open wall view (${_plural(wall.tiling.regions.length, 'area')}, ${_plural(wall.openings.length, 'opening')})'),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final r = result(false);
              if (r != null) Navigator.pop(c, r);
            },
            child: const Text('Save'),
          ),
        ],
      );
    }),
  );
}

class FloorDialogResult {
  final double width, height;
  final String? tileId;
  final bool openFloor;
  FloorDialogResult(this.width, this.height, this.tileId, this.openFloor);
}

Future<FloorDialogResult?> showFloorDialog(BuildContext context, Size size, String? tileId) {
  final w = numCtrl(size.width), h = numCtrl(size.height);
  String? tile = tileId;
  return showDialog<FloorDialogResult>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      FloorDialogResult? result(bool open) {
        final ww = parseNum(w.text), hh = parseNum(h.text);
        if (ww == null || hh == null || ww <= 0 || hh <= 0) return null;
        return FloorDialogResult(ww, hh, tile, open);
      }

      return AlertDialog(
        title: const Text('Floor'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: NumberField(w, 'Width')),
              gap(),
              Expanded(child: NumberField(h, 'Depth')),
            ]),
            gap(4),
            Text('Changing these stretches the whole room.', style: Theme.of(c).textTheme.bodySmall),
            gap(),
            TilePicker(value: tile, onChanged: (v) => setState(() => tile = v), label: 'Floor tile'),
            gap(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final r = result(true);
                  if (r != null) Navigator.pop(c, r);
                },
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Draw tiled areas on the floor'),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final r = result(false);
              if (r != null) Navigator.pop(c, r);
            },
            child: const Text('Save'),
          ),
        ],
      );
    }),
  );
}

/// Returns 'delete', 'save' or null.
Future<String?> showFixtureDialog(BuildContext context, Fixture f) {
  final w = numCtrl(f.width), d = numCtrl(f.depth), h = numCtrl(f.height), e = numCtrl(f.elevation);
  final rot = numCtrl(((f.rotation * 180 / math.pi) % 360 + 360) % 360);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(f.label),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: NumberField(w, 'Width')),
            gap(),
            Expanded(child: NumberField(d, 'Depth')),
          ]),
          gap(),
          Row(children: [
            Expanded(child: NumberField(h, 'Height')),
            gap(),
            Expanded(child: NumberField(e, 'From floor')),
          ]),
          gap(),
          NumberField(rot, 'Rotation', suffix: '°'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete')),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            f.width = parseNum(w.text) ?? f.width;
            f.depth = parseNum(d.text) ?? f.depth;
            f.height = parseNum(h.text) ?? f.height;
            f.elevation = parseNum(e.text) ?? f.elevation;
            f.rotation = (parseNum(rot.text) ?? 0) * math.pi / 180;
            Navigator.pop(c, 'save');
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<FixtureType?> pickFixtureType(BuildContext context, IconData Function(FixtureType) icon) {
  return showModalBottomSheet<FixtureType>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final t in FixtureType.values)
              SizedBox(
                width: 100,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.pop(c, t),
                  child: Column(children: [
                    Icon(icon(t), size: 32),
                    gap(6),
                    Text(fixtureSpecs[t]!.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Returns 'delete', 'save' or null. Edits [o] in place on save.
Future<String?> showOpeningDialog(BuildContext context, Opening o) {
  final x = numCtrl(o.x), y = numCtrl(o.y), w = numCtrl(o.width), h = numCtrl(o.height);
  var type = o.type;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Door / window'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<OpeningType>(
              segments: const [
                ButtonSegment(value: OpeningType.door, label: Text('Door'), icon: Icon(Icons.door_front_door_outlined)),
                ButtonSegment(value: OpeningType.window, label: Text('Window'), icon: Icon(Icons.window_outlined)),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            gap(),
            Row(children: [
              Expanded(child: NumberField(w, 'Width')),
              gap(),
              Expanded(child: NumberField(h, 'Height')),
            ]),
            gap(),
            Row(children: [
              Expanded(child: NumberField(x, 'From wall start')),
              gap(),
              Expanded(child: NumberField(y, 'From floor')),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              o
                ..type = type
                ..x = parseNum(x.text) ?? o.x
                ..y = parseNum(y.text) ?? o.y
                ..width = parseNum(w.text) ?? o.width
                ..height = parseNum(h.text) ?? o.height;
              Navigator.pop(c, 'save');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Asks for a tile for a drawn area. Returns the tile id, '' to delete, or null.
Future<String?> showRegionDialog(BuildContext context, String? current, {bool canDelete = true}) {
  String? tile = current;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Tiles for this area'),
        content: SizedBox(
          width: 360,
          child: TilePicker(value: tile, allowNone: false, onChanged: (v) => setState(() => tile = v)),
        ),
        actions: [
          if (canDelete) TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Delete area')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: tile == null ? null : () => Navigator.pop(c, tile),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

String _plural(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';
