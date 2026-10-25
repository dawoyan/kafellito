import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../screens/tile_edit_screen.dart';
import '../store.dart';

final Map<String, Uint8List> _bytesCache = {};

Uint8List? tileBytes(Tile t) {
  if (t.imageBase64 == null) return null;
  final key = '${t.id}:${t.imageBase64!.length}';
  return _bytesCache.putIfAbsent(key, () => base64Decode(t.imageBase64!));
}

/// Small square preview of a tile: its photo, or its colour.
class TileSwatch extends StatelessWidget {
  final Tile? tile;
  final double size;
  const TileSwatch(this.tile, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final t = tile;
    final bytes = t == null ? null : tileBytes(t);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t?.color ?? Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black26),
      ),
      clipBehavior: Clip.antiAlias,
      child: t == null
          ? Icon(Icons.block, size: size * 0.6, color: Colors.black38)
          : bytes == null
              ? null
              : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

/// Dropdown of library tiles with an optional "no tiles" entry and a shortcut
/// to add a new tile.
class TilePicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowNone;
  final String label;

  const TilePicker({super.key, required this.value, required this.onChanged, this.allowNone = true, this.label = 'Tile'});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final ids = store.tiles.map((t) => t.id).toSet();
    final v = ids.contains(value) ? value : null;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: v,
            key: ValueKey('tp-$v-${store.tiles.length}'),
            isExpanded: true,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
            items: [
              if (allowNone)
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Row(children: [TileSwatch(null, size: 22), SizedBox(width: 8), Text('No tiles')]),
                ),
              for (final t in store.tiles)
                DropdownMenuItem<String?>(
                  value: t.id,
                  child: Row(children: [
                    TileSwatch(t, size: 22),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.label, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
        IconButton(
          tooltip: 'New tile',
          icon: const Icon(Icons.add_photo_alternate_outlined),
          onPressed: () async {
            final t = await Navigator.of(context).push<Tile>(MaterialPageRoute(builder: (_) => const TileEditScreen()));
            if (t != null) onChanged(t.id);
          },
        ),
      ],
    );
  }
}

class NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool autofocus;
  final bool signed;
  final ValueChanged<String>? onSubmitted;
  const NumberField(this.controller, this.label,
      {super.key, this.suffix = 'cm', this.autofocus = false, this.signed = false, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onSubmitted: onSubmitted,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(signed ? r'[-0-9.,]' : r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder(), isDense: true),
      onTap: () => controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length),
    );
  }
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

TextEditingController numCtrl(double v) => TextEditingController(text: fmtNum((v * 10).roundToDouble() / 10));

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

Widget gap([double h = 12]) => SizedBox(height: h, width: h);
