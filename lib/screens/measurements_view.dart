import 'package:flutter/material.dart';

import '../geometry.dart';
import '../models.dart';
import '../store.dart';
import '../surfaces.dart';
import '../widgets/common.dart';

class MeasurementsView extends StatelessWidget {
  final Project project;
  final int revision;
  const MeasurementsView({super.key, required this.project, required this.revision});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final p = project;
    if (!p.closed || p.points.length < 3) {
      return const Center(child: Text('Finish the room plan to see measurements.'));
    }
    final counts = countTiles(p, store.tileMap).values.toList()
      ..sort((a, b) => a.tile.name.compareTo(b.tile.name));
    final theme = Theme.of(context);
    final floorArea = polygonArea(p.points) / 10000;
    var wallArea = 0.0;
    for (var i = 0; i < p.edgeCount; i++) {
      wallArea += p.wallLength(i) * p.walls[i].height / 10000;
      for (final o in p.walls[i].openings) {
        wallArea -= o.width * o.height / 10000;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _Stat('Floor', '${floorArea.toStringAsFixed(2)} m²'),
          _Stat('Walls', '${wallArea.toStringAsFixed(2)} m²'),
          _Stat('Grout', '${fmtNum(p.groutMm)} mm'),
          _Stat('Extra for waste', '${fmtNum(p.wastePct)} %'),
        ]),
        gap(20),
        Text('Tiles to buy', style: theme.textTheme.titleMedium),
        gap(8),
        if (counts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No tiles assigned yet. Double-tap a wall or the floor in the plan to choose tiles.'),
            ),
          ),
        for (final c in counts)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  TileSwatch(c.tile, size: 44),
                  gap(),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.tile.name.isEmpty ? 'Tile' : c.tile.name, style: theme.textTheme.titleSmall),
                      Text('${c.tile.code.isEmpty ? '—' : c.tile.code} · ${fmtNum(c.tile.widthCm)}×${fmtNum(c.tile.heightCm)} cm',
                          style: theme.textTheme.bodySmall),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${c.withWaste(p.wastePct)} pcs',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (c.boxes(p.wastePct) != null)
                      Text('${c.boxes(p.wastePct)} ${c.boxes(p.wastePct) == 1 ? 'box' : 'boxes'}', style: theme.textTheme.bodySmall),
                  ]),
                ]),
                const Divider(height: 20),
                _row('Area covered', '${(c.areaCm2 / 10000).toStringAsFixed(2)} m²'),
                _row('Whole tiles', '${c.full}'),
                _row('Cut tiles', '${c.cut}'),
                _row('With ${fmtNum(p.wastePct)}% extra', '${c.withWaste(p.wastePct)}'),
                gap(6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in c.perSurface.entries)
                    Chip(
                      label: Text('${e.key}: ${e.value}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ]),
              ]),
            ),
          ),
        gap(20),
        Text('Walls', style: theme.textTheme.titleMedium),
        gap(8),
        Card(
          child: Column(children: [
            for (var i = 0; i < p.edgeCount; i++)
              ListTile(
                dense: true,
                leading: TileSwatch(store.tile(p.walls[i].tiling.tileId), size: 24),
                title: Text('Wall ${i + 1}'),
                subtitle: Text('${fmtNum((p.wallLength(i) * 10).roundToDouble() / 10)} × ${fmtNum(p.walls[i].height)} cm'
                    '${p.walls[i].openings.isEmpty ? '' : ' · ${p.walls[i].openings.length} openings'}'),
                trailing: Text(
                    '${((p.wallLength(i) * p.walls[i].height - p.walls[i].openings.fold(0.0, (a, o) => a + o.width * o.height)) / 10000).toStringAsFixed(2)} m²'),
              ),
          ]),
        ),
        gap(12),
        Text(
          'A tile that is only partly inside an area counts as one cut tile. Offcuts are not reused, so real needs may be a little lower.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.textTheme.bodySmall),
        Text(value, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
