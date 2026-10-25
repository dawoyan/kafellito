import 'package:flutter/material.dart';

import '../store.dart';
import '../widgets/common.dart';
import 'tile_edit_screen.dart';

class TileLibraryView extends StatelessWidget {
  const TileLibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (store.tiles.isEmpty) {
      return const Center(child: Text('No tiles yet. Tap + to photograph one.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
      itemCount: store.tiles.length,
      itemBuilder: (context, i) {
        final t = store.tiles[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TileEditScreen(tile: t))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: LayoutBuilder(builder: (c, cons) => TileSwatch(t, size: cons.maxWidth))),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name.isEmpty ? 'Tile' : t.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                      Text('${t.code.isEmpty ? '—' : t.code} · ${fmtCm(t.widthCm)}×${fmtCm(t.heightCm)} cm',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String fmtCm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
