import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import 'crop_screen.dart';
import '../i18n.dart';

const _swatches = [
  0xFFF2F0EA,
  0xFFD9D4C7,
  0xFFC9B79C,
  0xFF8D7B68,
  0xFF5D5C61,
  0xFF2B2B2E,
  0xFF2F6C9E,
  0xFF7FB3D5,
  0xFF3E8E7E,
  0xFFA8C69F,
  0xFFB5523B,
  0xFFE3B23C,
];

/// Creates or edits a library tile. Pops with the saved tile.
/// With [copy] set, [tile] is a new unsaved copy rather than a library tile.
class TileEditScreen extends StatefulWidget {
  final Tile? tile;
  final bool copy;
  const TileEditScreen({super.key, this.tile, this.copy = false});

  @override
  State<TileEditScreen> createState() => _TileEditScreenState();
}

class _TileEditScreenState extends State<TileEditScreen> {
  late final Tile _t = widget.tile == null ? Tile() : Tile.fromJson(widget.tile!.toJson());
  late final _code = TextEditingController(text: _t.code);
  late final _name = TextEditingController(text: _t.name);
  late final _w = numCtrl(_t.widthCm);
  late final _h = numCtrl(_t.heightCm);
  late final _ppb = TextEditingController(text: _t.piecesPerBox?.toString() ?? '');

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 90);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      final w = parseNum(_w.text), h = parseNum(_h.text);
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => CropScreen(bytes: bytes, aspect: (w != null && h != null && h > 0) ? w / h : null),
        ),
      );
      if (cropped == null) return;
      final avg = await AppStore.averageColor(cropped);
      setState(() {
        _t.imageBase64 = base64Encode(cropped);
        _t.colorValue = avg;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not get photo: {e}', {'e': e}))));
      }
    }
  }

  void _save() {
    final w = parseNum(_w.text), h = parseNum(_h.text);
    if (w == null || h == null || w <= 0 || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Enter the tile width and height'))));
      return;
    }
    _t
      ..code = _code.text.trim()
      ..name = _name.text.trim()
      ..widthCm = w
      ..heightCm = h
      ..piecesPerBox = int.tryParse(_ppb.text.trim());
    AppScope.read(context).upsertTile(_t);
    Navigator.pop(context, _t);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = tileBytes(_t);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tile == null || widget.copy ? tr('New tile') : tr('Edit tile')),
        actions: [
          if (widget.tile != null && !widget.copy)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                  context,
                  tr('Delete tile?'),
                  tr('It will be removed from every room that uses it.'),
                )) {
                  if (!context.mounted) return;
                  AppScope.read(context).deleteTile(_t.id);
                  Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: _t.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.contain)
                  : const Center(child: Icon(Icons.photo_camera_outlined, size: 48, color: Colors.black38)),
            ),
          ),
          gap(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: Text(tr('Take photo')),
                ),
              ),
              gap(),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(tr('Gallery')),
                ),
              ),
            ],
          ),
          if (bytes != null)
            TextButton(onPressed: () => setState(() => _t.imageBase64 = null), child: Text(tr('Remove photo'))),
          gap(),
          Row(
            children: [
              Expanded(child: NumberField(_w, tr('Width'))),
              gap(),
              Expanded(child: NumberField(_h, tr('Height'))),
            ],
          ),
          gap(),
          TextField(
            controller: _code,
            decoration: InputDecoration(labelText: tr('Item code'), border: OutlineInputBorder(), isDense: true),
          ),
          gap(),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Name'), border: OutlineInputBorder(), isDense: true),
          ),
          gap(),
          TextField(
            controller: _ppb,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('Pieces per box (optional)'),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (bytes == null) ...[
            gap(16),
            Text(tr('Colour (used when there is no photo)'), style: Theme.of(context).textTheme.labelLarge),
            gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _swatches)
                  GestureDetector(
                    onTap: () => setState(() => _t.colorValue = c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _t.colorValue == c ? Colors.teal : Colors.black26,
                          width: _t.colorValue == c ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          gap(24),
          FilledButton(onPressed: _save, child: Text(tr('Save tile'))),
        ],
      ),
    );
  }
}
