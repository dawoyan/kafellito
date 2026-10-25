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
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text(tr('Collections'), style: theme.textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: () => showCollectionDialog(context, null),
                  icon: const Icon(Icons.add),
                  label: Text(tr('New collection')),
                ),
              ],
            ),
          ),
        ),
        if (store.collections.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr('Group a wall, floor and decor tile to lay a whole room at once.'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: [
                  for (final c in store.collections)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: CollectionCard(c, onTap: () => showCollectionDialog(context, c)),
                    ),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(tr('Tiles'), style: theme.textTheme.titleMedium),
          ),
        ),
        if (store.tiles.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(tr('No tiles yet. Tap + to photograph one.'))),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          sliver: SliverGrid.builder(
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
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              '${t.code.isEmpty ? '—' : t.code} · ${fmtCm(t.widthCm)}×${fmtCm(t.heightCm)} ${tr('cm')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A collection shown as its wall, floor and decor swatches with its name.
class CollectionCard extends StatelessWidget {
  final TileCollection c;
  final VoidCallback? onTap;
  final bool selected;
  const CollectionCard(this.c, {super.key, this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: selected
          ? RoundedRectangleBorder(
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final id in [c.wallTileId, c.floorTileId, c.decorTileId])
                    Padding(padding: const EdgeInsets.only(right: 4), child: TileSwatch(store.tile(id), size: 34)),
                ],
              ),
              gap(6),
              SizedBox(
                width: 112,
                child: Text(
                  c.name.isEmpty ? tr('Collection') : c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Creates ([c] null) or edits a tile collection.
Future<void> showCollectionDialog(BuildContext context, TileCollection? c) {
  final store = AppScope.read(context);
  final edit = c == null ? TileCollection() : TileCollection.fromJson(c.toJson());
  final name = TextEditingController(text: edit.name);
  final decorH = numCtrl(edit.decorHeightCm);
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(c == null ? tr('New collection') : tr('Collection')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('Name'), border: OutlineInputBorder(), isDense: true),
                ),
                gap(),
                TilePicker(
                  value: edit.wallTileId,
                  label: tr('Wall tile'),
                  onChanged: (v) => setState(() => edit.wallTileId = v),
                ),
                gap(),
                TilePicker(
                  value: edit.floorTileId,
                  label: tr('Floor tile'),
                  onChanged: (v) => setState(() => edit.floorTileId = v),
                ),
                gap(),
                TilePicker(
                  value: edit.decorTileId,
                  label: tr('Decor tile'),
                  onChanged: (v) => setState(() => edit.decorTileId = v),
                ),
                if (edit.decorTileId != null) ...[gap(), NumberField(decorH, tr('Decor band from floor'))],
              ],
            ),
          ),
        ),
        actions: [
          if (c != null)
            TextButton(
              onPressed: () {
                store.deleteCollection(c.id);
                Navigator.pop(ctx);
              },
              child: Text(tr('Delete')),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () {
              edit
                ..name = name.text.trim()
                ..decorHeightCm = parseNum(decorH.text) ?? edit.decorHeightCm;
              store.upsertCollection(edit);
              Navigator.pop(ctx);
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
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
