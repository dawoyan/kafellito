import 'package:flutter/material.dart';

import '../geometry.dart';
import '../models.dart';
import '../store.dart';
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = rooms[i];
        final area = p.closed && p.points.length >= 3 ? polygonArea(p.points) / 10000 : 0.0;
        return Card(
          child: ListTile(
            leading: SizedBox(width: 56, height: 56, child: CustomPaint(painter: _Thumb(p))),
            title: Text(p.name),
            subtitle: Text(
              p.closed
                  ? tr('{n} walls · {area} m² floor', {'n': p.points.length, 'area': area.toStringAsFixed(2)})
                  : tr('Plan not finished'),
            ),
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
