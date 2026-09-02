import 'dart:ui' show Color;

/// The minimap's own chrome colours.
///
/// Read off the canvas background rather than off `Theme.of`, exactly as
/// `CommentView` does and for the same reason: a host may run a light app
/// around a dark canvas, or the other way about, and the panel has to stay
/// legible against the canvas it is sitting on rather than against the app.
///
/// Nothing here is added to `NodeEditorTheme`. The one thing the map takes
/// from the theme is `selectionColor`, which it *must* share or the map lies
/// about which node is selected.
class MinimapPalette {
  const MinimapPalette({
    required this.surface,
    required this.bar,
    required this.ink,
    required this.edge,
    required this.shade,
    required this.node,
    required this.viewportBorder,
  });

  /// The panel body, behind the map.
  final Color surface;

  /// The action bar.
  final Color bar;

  /// Writing and icons on the bar.
  final Color ink;

  /// The panel's outline, and the grip.
  final Color edge;

  /// The wash over everything the canvas is not currently showing.
  final Color shade;

  /// A node with no colour of its own.
  final Color node;

  /// The "you are here" rectangle.
  final Color viewportBorder;

  static const MinimapPalette onDark = MinimapPalette(
    surface: Color(0xFF1B1E24),
    bar: Color(0xFF272B33),
    ink: Color(0xFFF2F3F5),
    edge: Color(0xFF3A404B),
    shade: Color(0x8C0E1015),
    node: Color(0xFF8B93A7),
    viewportBorder: Color(0xFFDDE1E8),
  );

  static const MinimapPalette onLight = MinimapPalette(
    surface: Color(0xFFFFFFFF),
    bar: Color(0xFFE7E9EF),
    ink: Color(0xFF1B1E24),
    edge: Color(0xFFC3C8D2),
    shade: Color(0x593B4252),
    node: Color(0xFF7E869B),
    viewportBorder: Color(0xFF2C3140),
  );

  static MinimapPalette forCanvas(Color background) =>
      background.computeLuminance() > 0.5 ? onLight : onDark;
}
