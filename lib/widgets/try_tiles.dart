import 'package:flutter/material.dart';

import '../i18n.dart';
import '../models.dart';
import '../screens/tile_library_screen.dart';
import '../store.dart';
import '../surfaces.dart';
import 'common.dart';

/// Quick tile swaps for showing a client alternatives: lay a collection or
/// replace one tile with another everywhere in the room. [change] wraps each
/// edit so it can be undone; [show3d] closes the sheet and opens the 3D view.
class TryTilesSheet extends StatelessWidget {
  final Project project;
  final void Function(VoidCallback edit) change;
  final VoidCallback show3d;
  const TryTilesSheet({super.key, required this.project, required this.change, required this.show3d});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final p = store.projects.where((e) => e.id == project.id).firstOrNull ?? project;
    final used = store.countsFor(p).values.map((c) => c.tile).toList()..sort((a, b) => a.name.compareTo(b.name));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Try other tiles'), style: theme.textTheme.titleLarge),
            gap(4),
            Text(
              tr('Changes are only a try-out until you keep them. Revert brings back the saved tiles.'),
              style: theme.textTheme.bodySmall,
            ),
            if (store.collections.isNotEmpty) ...[
              gap(16),
              Text(tr('Lay a collection'), style: theme.textTheme.titleSmall),
              gap(6),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in store.collections)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CollectionCard(
                          c,
                          selected: p.collectionId == c.id,
                          onTap: () => change(() => applyCollection(p, c, store.tileMap)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            gap(16),
            Text(tr('Tiles in this room'), style: theme.textTheme.titleSmall),
            gap(6),
            if (used.isEmpty) Text(tr('No tiles assigned yet.'), style: theme.textTheme.bodySmall),
            for (final t in used)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TilePicker(
                  key: ValueKey('swap-${t.id}'),
                  value: t.id,
                  allowNone: false,
                  label: tr('Replace {tile}', {'tile': t.name.isEmpty ? tr('Tile') : t.name}),
                  onChanged: (v) {
                    if (v != null && v != t.id) change(() => replaceTile(p, t.id, v));
                  },
                ),
              ),
            gap(12),
            FilledButton.icon(onPressed: show3d, icon: const Icon(Icons.view_in_ar), label: Text(tr('See in 3D'))),
          ],
        ),
      ),
    );
  }
}
