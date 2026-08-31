import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../geometry/viewport_transform.dart';
import '../theme/node_editor_theme.dart';

/// Loads and configures the background grid's fragment shader.
///
/// The [FragmentProgram] is compiled once per process and cached; each editor
/// takes its own [FragmentShader] from it, because uniforms are per-instance
/// state and two editors painting in the same frame would otherwise clobber
/// each other.
abstract final class GridShader {
  /// Keys the shader may be bundled under, most likely first.
  ///
  /// Shader assets keep the `lib/` segment the pubspec declares them with,
  /// unlike ordinary package assets — and the `packages/` prefix only appears
  /// when this package is a dependency, not when it is the root (its own
  /// tests). Both were verified against a built AssetManifest.
  static const List<String> assetKeys = <String>[
    'packages/fl_nodes_v2/lib/shaders/grid.frag',
    'lib/shaders/grid.frag',
  ];

  /// The key the program actually loaded from, once known.
  static String? resolvedAssetKey;

  static FragmentProgram? _program;
  static Future<FragmentProgram?>? _pending;
  static bool _unavailable = false;

  /// Compiles the program, or returns null where shaders are not available.
  ///
  /// Failure is not fatal: [GridPainter] falls back to drawing lines on the
  /// CPU, so a missing shader costs performance rather than correctness.
  static Future<FragmentProgram?> load() {
    if (_unavailable) return Future<FragmentProgram?>.value();
    final program = _program;
    if (program != null) return Future<FragmentProgram?>.value(program);

    return _pending ??= _loadFirstAvailable();
  }

  static Future<FragmentProgram?> _loadFirstAvailable() async {
    final failures = <String>[];
    for (final key in assetKeys) {
      try {
        final program = await FragmentProgram.fromAsset(key);
        resolvedAssetKey = key;
        return _program = program;
      } catch (error) {
        failures.add('  $key\n    $error');
      }
    }
    _unavailable = true;
    // Report every attempt. Naming only the last one points at the fallback
    // key rather than the one that actually matters to an application.
    debugPrint(
      'fl_nodes_v2: falling back to the CPU grid painter; the grid\n'
      'still renders, only less efficiently. No shader asset resolved:\n'
      '${failures.join('\n')}\n'
      'If the pubspec gained its `shaders:` entry while the app was running, '
      'a hot reload will not bundle it — restart the app.',
    );
    return null;
  }

  /// A fresh shader instance, or null if the program has not loaded.
  static FragmentShader? createShader() => _program?.fragmentShader();

  /// Uniform slots, in declaration order. The engine exposes uniforms as one
  /// flat float array, so these indices have to track the `.frag` source.
  static const int _origin = 0; // vec2
  static const int _spacing = 2;
  static const int _majorEvery = 3;
  static const int _lineWidth = 4;
  static const int _background = 5; // vec4
  static const int _minorColor = 9; // vec4
  static const int _majorColor = 13; // vec4
  static const int _minorOpacity = 17;

  /// Below this on-screen spacing minor lines start to alias, so they are
  /// faded out over the range rather than popping off at a threshold.
  static const double _minorFadeStart = 4;
  static const double _minorFadeEnd = 11;

  /// Whether the grid is dense enough that even major lines are noise.
  static bool isTooDense(NodeEditorTheme theme, double scale) {
    final majorEvery = theme.gridMajorEvery < 1 ? 1 : theme.gridMajorEvery;
    return theme.gridSpacing * scale * majorEvery < _minorFadeStart;
  }

  static void configure(
    FragmentShader shader,
    ViewportTransform viewport,
    NodeEditorTheme theme,
  ) {
    final spacing = theme.gridSpacing * viewport.scale;
    final majorEvery = (theme.gridMajorEvery < 1 ? 1 : theme.gridMajorEvery)
        .toDouble();
    final minorOpacity =
        ((spacing - _minorFadeStart) / (_minorFadeEnd - _minorFadeStart)).clamp(
          0.0,
          1.0,
        );

    shader
      ..setFloat(_origin, viewport.offset.dx)
      ..setFloat(_origin + 1, viewport.offset.dy)
      ..setFloat(_spacing, spacing)
      ..setFloat(_majorEvery, majorEvery)
      ..setFloat(_lineWidth, 1)
      ..setFloat(_minorOpacity, minorOpacity);

    _setColor(shader, _background, theme.background);
    _setColor(shader, _minorColor, theme.gridLine);
    _setColor(shader, _majorColor, theme.gridLineMajor);
  }

  /// Fragment shaders work in premultiplied alpha.
  static void _setColor(FragmentShader shader, int index, Color color) {
    final a = color.a;
    shader
      ..setFloat(index, color.r * a)
      ..setFloat(index + 1, color.g * a)
      ..setFloat(index + 2, color.b * a)
      ..setFloat(index + 3, a);
  }
}
