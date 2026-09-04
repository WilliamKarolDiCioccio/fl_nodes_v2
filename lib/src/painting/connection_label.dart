import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../geometry/viewport_transform.dart';

/// Where a connection's caption sits on screen, and how big it is.
///
/// The painter draws captions and the editor hit-tests them, and both come
/// through here. A caption is canvas text rather than a widget, so the only
/// thing that makes it tappable is agreeing on the box it was drawn in —
/// computing that twice would let the two drift apart.
abstract final class ConnectionLabel {
  /// Below this zoom captions stop being readable and are not drawn at all.
  ///
  /// They are not tappable then either: nothing is on screen to aim at.
  static const double detailScaleThreshold = 0.45;

  /// Drawn in place of a caption on an editable link that has none yet, so
  /// there is something to aim at when giving it one.
  static const String placeholder = '+';

  /// What is drawn for a link, and where — or null when nothing is.
  ///
  /// One call answers both "what does the painter put here" and "did the tap
  /// land on it", which is the only reason the two can be trusted to agree.
  ///
  /// [text] is the caption already resolved by the registry, so this does not
  /// care whether it was derived or typed.
  static ConnectionCaption? captionFor({
    required String? text,
    required Offset? anchor,
    required bool editable,
    required ViewportTransform viewport,
    required TextStyle? style,
  }) {
    final hasText = text != null && text.isNotEmpty;
    if (!hasText && !editable) return null;

    final caption = hasText ? text : placeholder;
    final resolved = hasText ? style : _dim(style);
    final rect = rectFor(
      anchor: anchor,
      text: caption,
      viewport: viewport,
      style: resolved,
    );
    return rect == null
        ? null
        : ConnectionCaption(text: caption, style: resolved, rect: rect);
  }

  /// Subdued, so an empty captionable link reads as an invitation rather than
  /// as content.
  static TextStyle? _dim(TextStyle? base) {
    final style = base ?? const TextStyle(fontSize: _defaultFontSize);
    final color = style.color;
    return color == null
        ? style
        : style.copyWith(color: color.withValues(alpha: 0.55));
  }

  /// Breathing room between the text and the plate behind it.
  static const double horizontalPadding = 5;
  static const double verticalPadding = 2;

  /// The widest a caption is ever drawn, in scene units at scale 1.
  ///
  /// Public because a host that arranges its own graph cannot get it any other
  /// way, and needs it: the caption sits at the midpoint of a curve, so the gap
  /// a layout leaves between two ranks has to be at least this wide or every
  /// caption is drawn over a node. It is a hard cap — the text is one line and
  /// ellipsised — so a layout can trust it rather than guess.
  static const double maxWidth = 160;
  static const double _defaultFontSize = 11;

  /// Lays [text] out the way it will be painted.
  ///
  /// Laying text out on every frame shows up in profiles quickly, and captions
  /// change far less often than the canvas repaints, so results are cached.
  static TextPainter layout(String text, TextStyle? style, double scale) {
    final rounded = (scale * 20).round();
    final key = '$rounded|${style?.hashCode ?? 0}|$text';
    final cached = _cache[key];
    if (cached != null) return cached;

    if (_cache.length >= _cacheCapacity) _cache.clear();
    final effective = (style ?? const TextStyle(fontSize: _defaultFontSize))
        .copyWith(
          fontSize:
              (style?.fontSize ?? _defaultFontSize) * math.min(scale, 1.0),
        );
    final painter = TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    _cache[key] = painter;
    return painter;
  }

  /// The on-screen box [text] occupies, or null when nothing is drawn.
  static Rect? rectFor({
    required Offset? anchor,
    required String? text,
    required ViewportTransform viewport,
    required TextStyle? style,
  }) {
    if (anchor == null || text == null || text.isEmpty) return null;
    if (viewport.scale < detailScaleThreshold) return null;

    final painter = layout(text, style, viewport.scale);
    return Rect.fromCenter(
      center: viewport.toScreen(anchor),
      width: painter.width + horizontalPadding * 2,
      height: painter.height + verticalPadding * 2,
    );
  }

  static const int _cacheCapacity = 256;
  static final Map<String, TextPainter> _cache = <String, TextPainter>{};
}

/// A connection's caption, as it is drawn.
@immutable
class ConnectionCaption {
  const ConnectionCaption({
    required this.text,
    required this.style,
    required this.rect,
  });

  final String text;
  final TextStyle? style;

  /// The on-screen box, including the plate's padding.
  final Rect rect;

  /// Where the text itself starts.
  Offset get textOrigin =>
      rect.topLeft +
      const Offset(
        ConnectionLabel.horizontalPadding,
        ConnectionLabel.verticalPadding,
      );
}
