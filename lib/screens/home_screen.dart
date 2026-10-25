import 'package:flutter/material.dart';

import '../geometry.dart';
import '../models.dart';
import '../store.dart';
import '../surfaces.dart';
import '../widgets/common.dart';
import 'project_screen.dart';
import 'settings_screen.dart';
import 'tile_edit_screen.dart';
import 'tile_library_screen.dart';
import '../i18n.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  Future<void> _newRoom() async {
    final store = AppScope.read(context);
    final ctrl = TextEditingController(text: tr('Room {n}', {'n': store.projects.length + 1}));
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('New room')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Name')),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(tr('Create'))),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final p = Project(name: name.trim().isEmpty ? tr('Room') : name.trim(), groutMm: store.defaultGapMm);
    store.upsertProject(p);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectScreen(projectId: p.id)));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon/icon.png', width: 32, height: 32, errorBuilder: (_, _, _) => const SizedBox()),
            const SizedBox(width: 10),
            Text(tr('Kafelito')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : _tab == 0
          ? const _RoomList()
          : const TileLibraryView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tab == 0
            ? _newRoom
            : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TileEditScreen())),
        icon: Icon(_tab == 0 ? Icons.add : Icons.add_a_photo_outlined),
        label: Text(_tab == 0 ? tr('New room') : tr('New tile')),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: tr('Rooms')),
          NavigationDestination(icon: Icon(Icons.grid_view), label: tr('Tiles')),
        ],
      ),
    );
  }
}

class _RoomList extends StatelessWidget {
  const _RoomList();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final rooms = [...store.projects]..sort((a, b) => b.updated.compareTo(a.updated));
    if (rooms.isEmpty) return Center(child: Text(tr('No rooms yet. Tap New room to draw one.')));
    final m2 = tr('m²');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: rooms.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == 0) return _Totals(rooms);
        final p = rooms[i - 1];
        final floor = floorAreaM2(p), walls = wallAreaM2(p);
        final tiled = store.countsFor(p).values.fold(0.0, (a, c) => a + c.areaCm2) / 10000;
        return Card(
          child: ListTile(
            leading: SizedBox(width: 56, height: 56, child: CustomPaint(painter: _Thumb(p))),
            title: Text(p.name),
            subtitle: Text(
              p.closed
                  ? '${tr('Floor {f} · walls {w} {m2}', {'f': floor.toStringAsFixed(2), 'w': walls.toStringAsFixed(2), 'm2': m2})}\n'
                        '${tr('Total {t} {m2} · tiled {a} {m2}', {'t': (floor + walls).toStringAsFixed(2), 'a': tiled.toStringAsFixed(2), 'm2': m2})}'
                  : tr('Plan not finished'),
            ),
            isThreeLine: p.closed,
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'delete' && await confirm(context, 'Delete ${p.name}?', 'This cannot be undone.')) {
                  store.deleteProject(p.id);
                } else if (v == 'copy') {
                  final c = p.clone()
                    ..id = newId()
                    ..name = tr('{name} copy', {'name': p.name});
                  store.upsertProject(c);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'copy', child: Text(tr('Duplicate'))),
                PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
              ],
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectScreen(projectId: p.id))),
          ),
        );
      },
    );
  }
}

/// Area and tiles to buy per tile type, summed over all rooms.
class _Totals extends StatelessWidget {
  final List<Project> rooms;
  const _Totals(this.rooms);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    final m2 = tr('m²');
    final area = <String, double>{}, pieces = <String, int>{};
    final tiles = <String, Tile>{};
    var floor = 0.0, walls = 0.0;
    for (final p in rooms) {
      floor += floorAreaM2(p);
      walls += wallAreaM2(p);
      for (final c in store.countsFor(p).values) {
        tiles[c.tile.id] = c.tile;
        area[c.tile.id] = (area[c.tile.id] ?? 0) + c.areaCm2 / 10000;
        pieces[c.tile.id] = (pieces[c.tile.id] ?? 0) + c.withWaste(p.wastePct);
      }
    }
    final ids = tiles.keys.toList()..sort((a, b) => tiles[a]!.name.compareTo(tiles[b]!.name));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('All rooms'), style: theme.textTheme.titleMedium),
            gap(4),
            Text(
              tr('Floor {f} · walls {w} · total {t} {m2}', {
                'f': floor.toStringAsFixed(2),
                'w': walls.toStringAsFixed(2),
                't': (floor + walls).toStringAsFixed(2),
                'm2': m2,
              }),
              style: theme.textTheme.bodySmall,
            ),
            if (ids.isNotEmpty) const Divider(height: 20),
            for (final id in ids)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    TileSwatch(tiles[id], size: 32),
                    gap(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tiles[id]!.label, overflow: TextOverflow.ellipsis),
                          Text('${area[id]!.toStringAsFixed(2)} $m2', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          tr('{n} pcs', {'n': pieces[id]}),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (boxesFor(tiles[id]!, pieces[id]!) case final b?)
                          Text(
                            '$b ${plural(b, tr('box'), tr('boxes2'), tr('boxes'))}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends CustomPainter {
  final Project p;
  _Thumb(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    if (p.points.length < 2) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x11000000));
      return;
    }
    final b = boundsOf(p.points);
    final s = (size.shortestSide - 8) / (b.longestSide == 0 ? 1 : b.longestSide);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-b.center.dx, -b.center.dy);
    final path = Path()..addPolygon(p.points, p.closed);
    if (p.closed) canvas.drawPath(path, Paint()..color = const Color(0x221F6F78));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / s
        ..color = const Color(0xFF1F6F78),
    );
  }

  @override
  bool shouldRepaint(covariant _Thumb old) => true;
}
