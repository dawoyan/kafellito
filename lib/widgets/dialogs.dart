import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../surfaces.dart';
import 'common.dart';
import '../i18n.dart';

Future<double?> showAngleDialog(BuildContext context, double current) {
  final ctrl = TextEditingController(text: '90')..selection = const TextSelection(baseOffset: 0, extentOffset: 2);
  void submit(BuildContext c) {
    final v = parseNum(ctrl.text);
    if (v != null && v > 0 && v < 360) Navigator.pop(c, v);
  }

  return showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Corner angle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NumberField(ctrl, tr('Angle'), suffix: '°', autofocus: true, onSubmitted: (_) => submit(c)),
          gap(8),
          Text(
            tr('Now {a}°. The opposite wall stretches to fit.', {'a': current.toStringAsFixed(1)}),
            style: Theme.of(c).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => submit(c), child: Text(tr('Set'))),
      ],
    ),
  );
}

class WallDialogResult {
  final double length;
  final double height;
  final LayoutChoice layout;
  final bool openWall;
  WallDialogResult(this.length, this.height, this.layout, this.openWall);
}

Future<WallDialogResult?> showWallDialog(BuildContext context, Project p, int index) {
  final wall = p.walls[index];
  final len = numCtrl(p.wallLength(index));
  final h = numCtrl(wall.height);
  final layout = LayoutChoice.ofBase(wall.tiling);
  final model = SurfaceModel.wall(p, index);
  return showDialog<WallDialogResult>(
    context: context,
    builder: (c) {
      WallDialogResult? result(bool open) {
        final l = parseNum(len.text), hh = parseNum(h.text);
        if (l == null || hh == null || l <= 0 || hh <= 0) return null;
        return WallDialogResult(l, hh, layout, open);
      }

      return AlertDialog(
        title: Text(tr('Wall {n}', {'n': index + 1})),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: NumberField(len, tr('Length'), autofocus: true)),
                    gap(),
                    Expanded(child: NumberField(h, tr('Height'))),
                  ],
                ),
                gap(),
                TileLayoutEditor(
                  value: layout,
                  project: p,
                  label: tr('Wall tile'),
                  preview: () => model.withTiling(layout.onBase(wall.tiling)),
                ),
                gap(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final r = result(true);
                      if (r != null) Navigator.pop(c, r);
                    },
                    icon: const Icon(Icons.open_in_full),
                    label: Text(
                      wall.tiling.regions.isEmpty && wall.openings.isEmpty
                          ? tr('Open wall view')
                          : tr('Open wall view ({areas}, {openings})', {
                              'areas': _count(wall.tiling.regions.length, 'area'),
                              'openings': _count(wall.openings.length, 'opening'),
                            }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () {
              final r = result(false);
              if (r != null) Navigator.pop(c, r);
            },
            child: Text(tr('Save')),
          ),
        ],
      );
    },
  );
}

class FloorDialogResult {
  final double width, height;
  final LayoutChoice layout;
  final bool openFloor;
  FloorDialogResult(this.width, this.height, this.layout, this.openFloor);
}

Future<FloorDialogResult?> showFloorDialog(BuildContext context, Project p, Size size) {
  final w = numCtrl(size.width), h = numCtrl(size.height);
  final layout = LayoutChoice.ofBase(p.floor);
  final model = SurfaceModel.floor(p);
  return showDialog<FloorDialogResult>(
    context: context,
    builder: (c) {
      FloorDialogResult? result(bool open) {
        final ww = parseNum(w.text), hh = parseNum(h.text);
        if (ww == null || hh == null || ww <= 0 || hh <= 0) return null;
        return FloorDialogResult(ww, hh, layout, open);
      }

      return AlertDialog(
        title: Text(tr('Floor')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: NumberField(w, tr('Width'))),
                    gap(),
                    Expanded(child: NumberField(h, tr('Depth'))),
                  ],
                ),
                gap(4),
                Text(tr('Changing these stretches the whole room.'), style: Theme.of(c).textTheme.bodySmall),
                gap(),
                TileLayoutEditor(
                  value: layout,
                  project: p,
                  label: tr('Floor tile'),
                  preview: () => model.withTiling(layout.onBase(p.floor)),
                ),
                gap(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final r = result(true);
                      if (r != null) Navigator.pop(c, r);
                    },
                    icon: const Icon(Icons.draw_outlined),
                    label: Text(tr('Draw tiled areas on the floor')),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () {
              final r = result(false);
              if (r != null) Navigator.pop(c, r);
            },
            child: Text(tr('Save')),
          ),
        ],
      );
    },
  );
}

/// Tile for the whole of [model] (a wall or the floor).
Future<LayoutChoice?> showBaseTileDialog(BuildContext context, Project p, SurfaceModel model) {
  final layout = LayoutChoice.ofBase(model.tiling);
  return showDialog<LayoutChoice>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(model.isFloor ? tr('Tiles for the whole floor') : tr('Tiles for the whole wall')),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: TileLayoutEditor(
            value: layout,
            project: p,
            preview: () => model.withTiling(layout.onBase(model.tiling)),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, layout), child: Text(tr('Save'))),
      ],
    ),
  );
}

/// Returns 'delete', 'save' or null.
Future<String?> showFixtureDialog(BuildContext context, Fixture f) {
  final w = numCtrl(f.width), d = numCtrl(f.depth), h = numCtrl(f.height), e = numCtrl(f.elevation);
  final rot = numCtrl(((f.rotation * 180 / math.pi) % 360 + 360) % 360);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(f.label)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: NumberField(w, tr('Width'))),
                gap(),
                Expanded(child: NumberField(d, tr('Depth'))),
              ],
            ),
            gap(),
            Row(
              children: [
                Expanded(child: NumberField(h, tr('Height'))),
                gap(),
                Expanded(child: NumberField(e, tr('From floor'))),
              ],
            ),
            gap(),
            NumberField(rot, tr('Rotation'), suffix: '°'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(tr('Delete'))),
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
        FilledButton(
          onPressed: () {
            f.width = parseNum(w.text) ?? f.width;
            f.depth = parseNum(d.text) ?? f.depth;
            f.height = parseNum(h.text) ?? f.height;
            f.elevation = parseNum(e.text) ?? f.elevation;
            f.rotation = (parseNum(rot.text) ?? 0) * math.pi / 180;
            Navigator.pop(c, 'save');
          },
          child: Text(tr('Save')),
        ),
      ],
    ),
  );
}

Future<FixtureType?> pickFixtureType(BuildContext context, IconData Function(FixtureType) icon) {
  return showModalBottomSheet<FixtureType>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
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
                  child: Column(
                    children: [
                      Icon(icon(t), size: 32),
                      gap(6),
                      Text(
                        tr(fixtureSpecs[t]!.label),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Returns 'delete', 'save' or null. Edits [o] in place on save. Positions are
/// shown as seen from inside the room; [mirrored] walls run right to left.
Future<String?> showOpeningDialog(BuildContext context, Opening o, double wallLength, {bool mirrored = false}) {
  final x = numCtrl(mirrored ? wallLength - o.x - o.width : o.x);
  final y = numCtrl(o.y), w = numCtrl(o.width), h = numCtrl(o.height);
  var type = o.type;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(tr('Door / window')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<OpeningType>(
                segments: [
                  ButtonSegment(
                    value: OpeningType.door,
                    label: Text(tr('Door')),
                    icon: Icon(Icons.door_front_door_outlined),
                  ),
                  ButtonSegment(
                    value: OpeningType.window,
                    label: Text(tr('Window')),
                    icon: Icon(Icons.window_outlined),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              gap(),
              Row(
                children: [
                  Expanded(child: NumberField(w, tr('Width'))),
                  gap(),
                  Expanded(child: NumberField(h, tr('Height'))),
                ],
              ),
              gap(),
              Row(
                children: [
                  Expanded(child: NumberField(x, tr('From left corner'))),
                  gap(),
                  Expanded(child: NumberField(y, tr('From floor'))),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(tr('Delete'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () {
              final width = parseNum(w.text) ?? o.width;
              final left = parseNum(x.text) ?? (mirrored ? wallLength - o.x - o.width : o.x);
              o
                ..type = type
                ..x = mirrored ? wallLength - left - width : left
                ..y = parseNum(y.text) ?? o.y
                ..width = width
                ..height = parseNum(h.text) ?? o.height;
              Navigator.pop(c, 'save');
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
}

/// Asks for the tile of a drawn area: region [index] of [model], or a new
/// area with [newPoints]. Returns the choice, one with no tile to delete the
/// area, or null.
Future<LayoutChoice?> showRegionDialog(
  BuildContext context,
  Project p,
  SurfaceModel model,
  LayoutChoice initial, {
  int? index,
  List<Offset>? newPoints,
}) {
  final layout = initial;
  SurfaceModel preview() {
    final t = model.tiling.copy();
    if (index != null) {
      layout.applyToRegion(t.regions[index]);
    } else {
      final r = Region(points: newPoints ?? const [], tileId: '');
      layout.applyToRegion(r);
      t.regions.add(r);
    }
    return model.withTiling(t);
  }

  return showDialog<LayoutChoice>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(tr('Tiles for this area')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: TileLayoutEditor(
              value: layout,
              project: p,
              allowNone: false,
              layer: index ?? model.tiling.regions.length,
              preview: preview,
              onChanged: () => setState(() {}),
            ),
          ),
        ),
        actions: [
          if (index != null)
            TextButton(onPressed: () => Navigator.pop(c, LayoutChoice()), child: Text(tr('Delete area'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: layout.tileId == null ? null : () => Navigator.pop(c, layout),
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
}

/// Tile, gap and direction chosen in a tile dialog. A null [gapMm] follows the
/// room's tile gap.
class LayoutChoice {
  String? tileId;
  double? gapMm;
  bool rotated;
  LayoutChoice({this.tileId, this.gapMm, this.rotated = false});

  factory LayoutChoice.ofBase(SurfaceTiling t) => LayoutChoice(tileId: t.tileId, gapMm: t.gapMm, rotated: t.rotated);
  factory LayoutChoice.ofRegion(Region r) => LayoutChoice(tileId: r.tileId, gapMm: r.gapMm, rotated: r.rotated);

  void applyToBase(SurfaceTiling t) => t
    ..tileId = tileId
    ..gapMm = gapMm
    ..rotated = rotated;

  /// A copy of [t] with this choice as its base tile.
  SurfaceTiling onBase(SurfaceTiling t) {
    final c = t.copy();
    applyToBase(c);
    return c;
  }

  void applyToRegion(Region r) => r
    ..tileId = tileId ?? r.tileId
    ..gapMm = gapMm
    ..rotated = rotated;
}

/// Picks a tile, its gap and direction, and shows how many tiles that layer
/// takes. [preview] builds the surface with [value] applied; [layer] is the
/// layer to count in it (-1 for the base).
class TileLayoutEditor extends StatefulWidget {
  final LayoutChoice value;
  final Project project;
  final SurfaceModel Function() preview;
  final int layer;
  final String label;
  final bool allowNone;
  final VoidCallback? onChanged;

  const TileLayoutEditor({
    super.key,
    required this.value,
    required this.project,
    required this.preview,
    this.layer = -1,
    this.label = 'Tile',
    this.allowNone = true,
    this.onChanged,
  });

  @override
  State<TileLayoutEditor> createState() => _TileLayoutEditorState();
}

class _TileLayoutEditorState extends State<TileLayoutEditor> {
  late final bool _followsRoom = widget.value.gapMm == null;
  late final _gap = numCtrl(widget.value.gapMm ?? widget.project.groutMm)..addListener(_gapChanged);

  void _gapChanged() {
    final v = parseNum(_gap.text);
    if (v == null || v < 0 || v > 50) return;
    widget.value.gapMm = _followsRoom && v == widget.project.groutMm ? null : v;
    _update();
  }

  void _update() {
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  void dispose() {
    _gap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final v = widget.value;
    final tile = store.tile(v.tileId);
    final theme = Theme.of(context);
    final c = tile == null ? null : countLayer(widget.preview(), widget.layer, store.tileMap);
    final waste = widget.project.wastePct;
    final withWaste = c == null ? 0 : ((c.full + c.cut) * (1 + waste / 100)).ceil();
    final boxes = tile == null ? null : boxesFor(tile, withWaste);
    String dims(bool rot) =>
        rot ? '${fmtNum(tile!.heightCm)}×${fmtNum(tile.widthCm)}' : '${fmtNum(tile!.widthCm)}×${fmtNum(tile.heightCm)}';
    IconData icon(bool rot) => (tile!.widthCm < tile.heightCm) != rot ? Icons.crop_portrait : Icons.crop_landscape;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TilePicker(
          value: v.tileId,
          allowNone: widget.allowNone,
          label: widget.label,
          onChanged: (id) {
            v.tileId = id;
            if (store.tile(id) case final t? when t.widthCm == t.heightCm) v.rotated = false;
            _update();
          },
        ),
        if (tile != null) ...[
          gap(),
          NumberField(_gap, tr('Tile gap'), suffix: 'mm'),
          if (tile.widthCm != tile.heightCm) ...[
            gap(),
            Text(tr('Tile direction'), style: theme.textTheme.bodySmall),
            gap(4),
            SegmentedButton<bool>(
              segments: [
                for (final rot in [false, true])
                  ButtonSegment(value: rot, icon: Icon(icon(rot)), label: Text(rot ? '${dims(rot)} · 90°' : dims(rot))),
              ],
              selected: {v.rotated},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                v.rotated = s.first;
                _update();
              },
            ),
          ],
          if (c != null) ...[
            gap(),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('{n} pcs', {'n': withWaste}) +
                        (boxes == null ? '' : ' · $boxes ${plural(boxes, tr('box'), tr('boxes2'), tr('boxes'))}'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    tr('{full} whole + {cut} cut, {p}% extra · {area} m²', {
                      'full': c.full,
                      'cut': c.cut,
                      'p': fmtNum(waste),
                      'area': (c.areaCm2 / 10000).toStringAsFixed(2),
                    }),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

String _count(int n, String word) => '$n ${plural(n, tr(word), tr('${word}s2'), tr('${word}s'))}';
