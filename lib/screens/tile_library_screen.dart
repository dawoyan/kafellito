import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import 'tile_edit_screen.dart';
import '../i18n.dart';

class TileLibraryView extends StatelessWidget {
  const TileLibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (store.tiles.isEmpty) {
      return Center(child: Text(tr('No tiles yet. Tap + to photograph one.')));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: store.tiles.length,
      itemBuilder: (context, i) {
        final t = store.tiles[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openTile(context, t),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(builder: (c, cons) => TileSwatch(t, size: cons.maxWidth)),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.name.isEmpty ? tr('Tile') : t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${t.code.isEmpty ? '—' : t.code} · ${fmtCm(t.widthCm)}×${fmtCm(t.heightCm)} ${tr('cm')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

/// Opens [t] for editing, or, when rooms use it, lists them so the user can
/// take it out of them or edit a copy instead.
Future<void> openTile(BuildContext context, Tile t) async {
  final nav = Navigator.of(context);
  void edit() => nav.push(MaterialPageRoute(builder: (_) => TileEditScreen(tile: t)));
  final store = AppScope.read(context);
  if (store.roomsUsing(t.id).isEmpty) return edit();
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TileInUseSheet(t),
  );
  if (action == 'edit') {
    edit();
  } else if (action == 'copy') {
    final c = Tile.fromJson(t.toJson())
      ..id = newId()
      ..name = tr('{name} copy', {'name': t.name.isEmpty ? tr('Tile') : t.name});
    nav.push(MaterialPageRoute(builder: (_) => TileEditScreen(tile: c, copy: true)));
  }
}

/// Pops with 'edit' once no room uses the tile, 'copy', or null.
class _TileInUseSheet extends StatelessWidget {
  final Tile t;
  const _TileInUseSheet(this.t);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final rooms = store.roomsUsing(t.id);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TileSwatch(t, size: 40),
                gap(),
                Expanded(child: Text(t.label, style: theme.textTheme.titleMedium)),
              ],
            ),
            gap(),
            if (rooms.isEmpty)
              Text(tr('Not used in any room now.'))
            else ...[
              Text(
                tr('Used in {n}', {
                  'n': '${rooms.length} ${plural(rooms.length, tr('room'), tr('rooms2'), tr('rooms'))}',
                }),
                style: theme.textTheme.titleSmall,
              ),
              gap(4),
              Text(
                tr('Remove it from these rooms to change or delete it, or change a copy instead.'),
                style: theme.textTheme.bodySmall,
              ),
              gap(8),
              for (final p in rooms)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.space_dashboard_outlined),
                  title: Text(p.name),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.remove_circle_outline),
                    label: Text(tr('Remove')),
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        tr('Remove {tile} from {room}?', {
                          'tile': t.name.isEmpty ? tr('Tile') : t.name,
                          'room': p.name,
                        }),
                        tr('Walls and floor with this tile become untiled and its drawn areas are deleted.'),
                        ok: tr('Remove'),
                      );
                      if (ok) store.removeTileFromRoom(p, t.id);
                    },
                  ),
                ),
            ],
            gap(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context, 'copy'), child: Text(tr('Copy and edit'))),
                gap(8),
                FilledButton(
                  onPressed: rooms.isEmpty ? () => Navigator.pop(context, 'edit') : null,
                  child: Text(tr('Edit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String fmtCm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
