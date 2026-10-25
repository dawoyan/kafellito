import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kafelito/models.dart';
import 'package:kafelito/screens/tile_library_screen.dart';
import 'package:kafelito/store.dart';

void main() {
  testWidgets('collection dialog saves picked tiles', (tester) async {
    final store = AppStore()
      ..tiles.addAll([
        Tile(name: 'White', widthCm: 30, heightCm: 60),
        Tile(name: 'Stone', widthCm: 60, heightCm: 60),
      ]);
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(onPressed: () => showCollectionDialog(c, null), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Classic');
    await tester.tap(find.text('No tiles').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('White (30×60)').last);
    await tester.pumpAndSettle();
    expect(find.text('White (30×60)'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.collections.single.name, 'Classic');
    expect(store.collections.single.wallTileId, store.tiles.first.id);
    await tester.pump(const Duration(seconds: 1));
  });
}
