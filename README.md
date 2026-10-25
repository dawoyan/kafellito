# Kafelito

Plan a room, choose tiles for the floor and every wall, walk through it in 3D,
and get the number of tiles to buy.

Built with Flutter, so the same code runs on Android now and iPhone later.

## What it does

- **Tile library.** Photograph a tile, frame it, and give it a size, item code and name.
- **Top view.** Tap to place the room's corners. Any shape and any angle works.
  - Double-tap a corner to set its angle (90° is prefilled). The opposite wall stretches to fit.
  - Double-tap a wall to set its length, height and tile, or open the wall view.
  - Double-tap the floor to set its size and tile.
  - Long-press a wall to add a corner, long-press a corner to remove it.
  - Untiled walls are thin lines, tiled walls are thick.
- **Wall and floor views.** Draw rectangles or any shape and give each its own tile.
  Add doors, windows, and fixtures (sink, toilet, shower, bathtub, washing machine, cabinet, mirror).
- **3D.** Walk around inside the room, or look at it from above.
- **Measurements.** Whole and cut tiles per tile type, with grout and a waste margin, and boxes to buy.

Everything is saved on the phone.

## Build

```sh
flutter pub get
flutter run              # on a connected phone or emulator
flutter build apk        # Android APK in build/app/outputs/flutter-apk/
flutter build ios        # needs a Mac with Xcode
```

Every push to `main` also builds an APK on GitHub Actions. Download it from the
run's **Artifacts** section.

## Code map

| Path | What is there |
| --- | --- |
| `lib/models.dart` | Tiles, rooms, walls, tiled areas, openings, fixtures |
| `lib/geometry.dart` | Polygon maths, corner angles, wall lengths |
| `lib/surfaces.dart` | Which tile covers each point of a surface, and the tile count |
| `lib/widgets/plan_editor.dart` | Top view editor |
| `lib/screens/surface_screen.dart` | Wall and floor editor |
| `lib/widgets/view3d.dart` | 3D view (drawn with Flutter's canvas, no 3D engine needed) |
| `lib/screens/measurements_view.dart` | Tile counts |
| `assets/icon/` | App icon source (`icon.svg`) |
