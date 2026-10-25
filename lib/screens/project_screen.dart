import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/plan_editor.dart';
import '../widgets/view3d.dart';
import 'measurements_view.dart';
import 'surface_screen.dart';

class ProjectScreen extends StatefulWidget {
  final String projectId;
  const ProjectScreen({super.key, required this.projectId});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  int _tab = 0;
  int _rev = 0;
  final List<String> _undo = [];
  final _planKey = GlobalKey<PlanEditorState>();

  AppStore get store => AppScope.read(context);
  Project get project => store.projects.firstWhere((p) => p.id == widget.projectId);

  void _snapshot() {
    _undo.add(jsonOf(project));
    if (_undo.length > 60) _undo.removeAt(0);
  }

  void _changed() {
    setState(() => _rev++);
    store.upsertProject(project);
  }

  void _doUndo() {
    if (_undo.isEmpty) return;
    final restored = Project.fromJson(decodeJson(_undo.removeLast()));
    store.upsertProject(restored);
    setState(() => _rev++);
  }

  Future<void> _openSurface(int? wall) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SurfaceScreen(project: project, wallIndex: wall, beforeChange: _snapshot, onChanged: _changed),
    ));
    setState(() => _rev++);
  }

  Future<void> _settings() async {
    final p = project;
    final name = TextEditingController(text: p.name);
    final grout = numCtrl(p.groutMm), waste = numCtrl(p.wastePct);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Room settings'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true)),
            gap(),
            NumberField(grout, 'Grout joint', suffix: 'mm'),
            gap(),
            NumberField(waste, 'Extra for waste', suffix: '%'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    _snapshot();
    p
      ..name = name.text.trim().isEmpty ? p.name : name.text.trim()
      ..groutMm = parseNum(grout.text) ?? p.groutMm
      ..wastePct = parseNum(waste.text) ?? p.wastePct;
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final p = store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    if (p == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(tooltip: 'Undo', onPressed: _undo.isEmpty ? null : _doUndo, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Room settings', onPressed: _settings, icon: const Icon(Icons.tune)),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _planTab(p),
          _tab == 1 ? Room3DView(project: p, revision: _rev) : const SizedBox(),
          _tab == 2 ? MeasurementsView(project: p, revision: _rev) : const SizedBox(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.architecture), label: 'Top view'),
          NavigationDestination(icon: Icon(Icons.view_in_ar), label: '3D'),
          NavigationDestination(icon: Icon(Icons.calculate_outlined), label: 'Measurements'),
        ],
      ),
    );
  }

  Widget _planTab(Project p) {
    final drawing = !p.closed;
    final hint = drawing
        ? (p.points.length < 3
            ? 'Tap to place the corners of the room.'
            : 'Tap the first corner (or Close) to finish the room.')
        : 'Double-tap a corner, wall, floor or fixture to edit. Long-press a wall to add a corner.';
    return Stack(children: [
      Positioned.fill(
        child: PlanEditor(
          key: _planKey,
          project: p,
          beforeChange: _snapshot,
          onChanged: _changed,
          openWall: (i) => _openSurface(i),
          openFloor: () => _openSurface(null),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        top: 8,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xE6FFFFFF), borderRadius: BorderRadius.circular(16)),
            child: Text(hint, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ),
        ),
      ),
      Positioned(
        left: 8,
        right: 8,
        bottom: 8,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (drawing) ...[
              FilledButton.tonalIcon(
                onPressed: p.points.isEmpty ? null : () => _planKey.currentState?.removeLastPoint(),
                icon: const Icon(Icons.backspace_outlined),
                label: const Text('Remove point'),
              ),
              gap(8),
              FilledButton.icon(
                onPressed: p.points.length < 3 ? null : () => _planKey.currentState?.closeRoom(),
                icon: const Icon(Icons.check),
                label: const Text('Close room'),
              ),
            ] else ...[
              FilledButton.tonalIcon(
                onPressed: () => _planKey.currentState?.addFixture(),
                icon: const Icon(Icons.bathtub_outlined),
                label: const Text('Add fixture'),
              ),
              gap(8),
              FilledButton.tonalIcon(
                onPressed: () => _openSurface(null),
                icon: const Icon(Icons.grid_on),
                label: const Text('Floor'),
              ),
              gap(8),
              FilledButton.tonalIcon(
                onPressed: () => _planKey.currentState?.removeLastPoint(),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Reopen plan'),
              ),
            ],
            gap(8),
            IconButton.filledTonal(
              tooltip: 'Fit to screen',
              onPressed: () => _planKey.currentState?.fit(),
              icon: const Icon(Icons.fit_screen),
            ),
          ]),
        ),
      ),
    ]);
  }
}
