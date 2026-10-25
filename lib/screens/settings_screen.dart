import 'package:flutter/material.dart';

import '../i18n.dart';
import '../store.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _gap;

  @override
  void initState() {
    super.initState();
    _gap = numCtrl(AppScope.read(context).defaultGapMm)..addListener(_saveGap);
  }

  @override
  void dispose() {
    _gap.dispose();
    super.dispose();
  }

  void _saveGap({bool applyToAll = false}) {
    final v = parseNum(_gap.text);
    if (v == null || v < 0) return;
    final store = AppScope.read(context);
    if (v == store.defaultGapMm && !applyToAll) return;
    store.setDefaultGap(v, applyToAll: applyToAll);
    if (applyToAll) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Tile gap set to {gap} mm in all rooms.', {'gap': fmtNumSafe(v)}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('Language'), style: theme.textTheme.titleMedium),
          gap(8),
          SegmentedButton<String>(
            segments: [for (final e in languages.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {store.lang},
            onSelectionChanged: (s) => store.setLanguage(s.first),
          ),
          gap(28),
          Text(tr('Default tile gap for new rooms'), style: theme.textTheme.titleMedium),
          gap(8),
          Row(
            children: [
              SizedBox(width: 140, child: NumberField(_gap, tr('Tile gap'), suffix: 'mm')),
              gap(),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _saveGap(applyToAll: true),
                  child: Text(tr('Apply to all rooms')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String fmtNumSafe(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
