import 'package:flutter/material.dart';

import '../export.dart';
import '../models.dart';
import '../store.dart';
import '../surfaces.dart';
import '../widgets/common.dart';
import '../widgets/plan_editor.dart';
import '../widgets/try_tiles.dart';
import '../widgets/view3d.dart';
import 'measurements_view.dart';
import 'surface_screen.dart';
import '../i18n.dart';

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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SurfaceScreen(project: project, wallIndex: wall, beforeChange: _snapshot, onChanged: _changed),
      ),
    );
    setState(() => _rev++);
  }

  // ---- tile try-out ----

  void _edit(VoidCallback fn) {
    _snapshot();
    fn();
    _changed();
  }

  Future<void> _tryTiles() async {
    final p = project;
    if (p.trialBase == null) _edit(() => p.trialBase = jsonOf(p));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => TryTilesSheet(
        project: p,
        change: _edit,
        show3d: () {
          Navigator.pop(c);
          setState(() => _tab = 1);
        },
      ),
    );
  }

  void _keepTrial() => _edit(() => project.trialBase = null);

  void _revertTrial() {
    final base = project.trialBase;
    if (base == null) return;
    _snapshot();
    final restored = Project.fromJson(decodeJson(base))..trialBase = null;
    store.upsertProject(restored);
    setState(() => _rev++);
  }

  /// Asks whether to keep or revert a running try-out. Returns false to stay.
  Future<bool> _finishTrial() async {
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Keep the tiles you tried?')),
        content: Text(tr('Revert brings back the tiles saved before the try-out.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Stay'))),
          TextButton(onPressed: () => Navigator.pop(c, 'revert'), child: Text(tr('Revert'))),
          FilledButton(onPressed: () => Navigator.pop(c, 'keep'), child: Text(tr('Keep'))),
        ],
      ),
    );
    if (r == 'keep') _keepTrial();
    if (r == 'revert') _revertTrial();
    return r != null;
  }

  Future<void> _settings() async {
    final p = project;
    final name = TextEditingController(text: p.name);
    final grout = numCtrl(p.groutMm), waste = numCtrl(p.wastePct);
    String? collection = store.collection(p.collectionId)?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(tr('Room settings')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('Name'), border: OutlineInputBorder(), isDense: true),
                ),
                gap(),
                NumberField(grout, tr('Tile gap'), suffix: 'mm'),
                gap(),
                NumberField(waste, tr('Extra for waste'), suffix: '%'),
                if (store.collections.isNotEmpty) ...[
                  gap(),
                  DropdownButtonFormField<String?>(
                    initialValue: collection,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Tile collection'),
                      helperText: tr('Choosing one lays it on the walls and floor.'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(value: null, child: Text(tr('None'))),
                      for (final col in store.collections)
                        DropdownMenuItem(value: col.id, child: Text(col.name.isEmpty ? tr('Collection') : col.name)),
                    ],
                    onChanged: (v) => setState(() => collection = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    _snapshot();
    p
      ..name = name.text.trim().isEmpty ? p.name : name.text.trim()
      ..groutMm = parseNum(grout.text) ?? p.groutMm
      ..wastePct = parseNum(waste.text) ?? p.wastePct;
    final col = store.collection(collection);
    if (col == null) {
      p.collectionId = null;
    } else if (col.id != p.collectionId) {
      applyCollection(p, col, store.tileMap);
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final p = store.projects.where((p) => p.id == widget.projectId).firstOrNull;
    if (p == null) return const Scaffold();
    final trying = p.trialBase != null;
    return PopScope(
      canPop: !trying,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _finishTrial() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(p.name),
          actions: [
            IconButton(tooltip: tr('Undo'), onPressed: _undo.isEmpty ? null : _doUndo, icon: const Icon(Icons.undo)),
            IconButton(
              tooltip: tr('Try other tiles'),
              onPressed: p.closed ? _tryTiles : null,
              icon: const Icon(Icons.style_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'settings') _settings();
                if (v == 'export') showExportSheet(context, p);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(leading: const Icon(Icons.tune), title: Text(tr('Room settings'))),
                ),
                PopupMenuItem(
                  value: 'export',
                  enabled: p.closed,
                  child: ListTile(leading: const Icon(Icons.ios_share), title: Text(tr('Export for customer'))),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (trying)
              Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.style_outlined, size: 20),
                      gap(10),
                      Expanded(child: Text(tr('Trying tiles. Not kept yet.'))),
                      TextButton(onPressed: _tryTiles, child: Text(tr('Swap'))),
                      TextButton(onPressed: _revertTrial, child: Text(tr('Revert'))),
                      FilledButton(onPressed: _keepTrial, child: Text(tr('Keep'))),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _planTab(p),
                  _tab == 1 ? Room3DView(project: p, revision: _rev) : const SizedBox(),
                  _tab == 2 ? MeasurementsView(project: p, revision: _rev) : const SizedBox(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(icon: Icon(Icons.architecture), label: tr('Top view')),
            NavigationDestination(icon: Icon(Icons.view_in_ar), label: tr('3D')),
            NavigationDestination(icon: Icon(Icons.calculate_outlined), label: tr('Measurements')),
          ],
        ),
      ),
    );
  }

  Widget _planTab(Project p) {
    final drawing = !p.closed;
    final hint = drawing
        ? (p.points.length < 3
              ? tr('Tap to place the corners of the room.')
              : tr('Tap the first corner (or Close) to finish the room.'))
        : tr('Double-tap a corner, wall, floor or fixture to edit. Long-press a wall to add a corner.');
    return Stack(
      children: [
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
            child: Row(
              children: [
                if (drawing) ...[
                  FilledButton.tonalIcon(
                    onPressed: p.points.isEmpty ? null : () => _planKey.currentState?.removeLastPoint(),
                    icon: const Icon(Icons.backspace_outlined),
                    label: Text(tr('Remove point')),
                  ),
                  gap(8),
                  FilledButton.icon(
                    onPressed: p.points.length < 3 ? null : () => _planKey.currentState?.closeRoom(),
                    icon: const Icon(Icons.check),
                    label: Text(tr('Close room')),
                  ),
                ] else ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _planKey.currentState?.addFixture(),
                    icon: const Icon(Icons.bathtub_outlined),
                    label: Text(tr('Add fixture')),
                  ),
                  gap(8),
                  FilledButton.tonalIcon(
                    onPressed: () => _openSurface(null),
                    icon: const Icon(Icons.grid_on),
                    label: Text(tr('Floor')),
                  ),
                  gap(8),
                  FilledButton.tonalIcon(
                    onPressed: () => _planKey.currentState?.removeLastPoint(),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(tr('Reopen plan')),
                  ),
                ],
                gap(8),
                IconButton.filledTonal(
                  tooltip: tr('Fit to screen'),
                  onPressed: () => _planKey.currentState?.fit(),
                  icon: const Icon(Icons.fit_screen),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
