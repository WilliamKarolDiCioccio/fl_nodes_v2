import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/node_group.dart';
import '../theme/node_editor_theme.dart';

/// One group: a translucent frame around its members, and the handle that
/// stands for it.
///
/// **The frame itself takes no pointer events.** It is drawn *below* the nodes
/// it surrounds, and the space between them is still canvas — a click there
/// belongs to the marquee, not to the group. Everything the group can be asked
/// to do goes through the handle, which is what makes "clicking nodes does the
/// usual thing" true without a single special case in the node path.
///
/// The handle sits in the frame's top padding band, which is
/// [NodeGroup.padding]`.top` deep and by construction holds no member. A
/// handle overlapping one could not be clicked at all, since the node paints
/// over it.
class GroupView extends StatelessWidget {
  const GroupView({
    super.key,
    required this.group,
    required this.theme,
    required this.isSelected,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onRename,
    required this.onColorPicked,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  /// Handle geometry. The handle is deliberately not the frame's width: it is
  /// a grip on a group, not a title bar over a window.
  static const double handleHeight = 26;
  static const double handleInset = 8;
  static const double maxNameWidth = 180;

  final NodeGroup group;
  final NodeEditorTheme theme;
  final bool isSelected;

  final void Function(bool additive) onTap;
  final void Function(Offset globalPosition) onSecondaryTap;
  final VoidCallback onRename;
  final ValueChanged<Color?> onColorPicked;
  final void Function(Offset globalPosition, bool additive) onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  static bool get _additivePressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
  }

  @override
  Widget build(BuildContext context) {
    final color = group.effectiveColor;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Faint on purpose: the frame is a backdrop, and anything
                // stronger competes with the nodes standing on it.
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? theme.selectionColor
                      : color.withValues(alpha: 0.45),
                  width: isSelected ? theme.selectionWidth : 1,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: handleInset,
          top: handleInset,
          child: _Handle(
            group: group,
            color: color,
            onTap: onTap,
            onSecondaryTap: onSecondaryTap,
            onRename: onRename,
            onColorPicked: onColorPicked,
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
          ),
        ),
      ],
    );
  }
}

/// The writing on a handle and on its dropdown arrow. Fixed, like the rest of
/// a group's chrome: every palette colour is dark enough to carry it.
const Color _ink = Color(0xFFF2F3F5);

/// Fully opaque, where the frame is not: it is the one part of a group that
/// has to be found and hit, over whatever the canvas is showing behind it.
class _Handle extends StatefulWidget {
  const _Handle({
    required this.group,
    required this.color,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onRename,
    required this.onColorPicked,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final NodeGroup group;
  final Color color;
  final void Function(bool additive) onTap;
  final void Function(Offset globalPosition) onSecondaryTap;
  final VoidCallback onRename;
  final ValueChanged<Color?> onColorPicked;
  final void Function(Offset globalPosition, bool additive) onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  DateTime? _lastTapAt;

  /// Selects on the first tap and synthesises the double tap itself, exactly
  /// as `NodeView` does and for the same reason: handing `onDoubleTap` to the
  /// [GestureDetector] puts a [DoubleTapGestureRecognizer] in the arena, and
  /// that one *holds* every single tap — including taps meant for the colour
  /// menu nested inside — until the double-tap timeout expires.
  void _handleTap() {
    widget.onTap(GroupView._additivePressed);

    final now = DateTime.now();
    final previous = _lastTapAt;
    if (previous != null && now.difference(previous) <= kDoubleTapTimeout) {
      _lastTapAt = null;
      widget.onRename();
    } else {
      _lastTapAt = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // From where the pointer went down, so the grip stays under the
        // cursor rather than trailing it by the touch slop.
        dragStartBehavior: DragStartBehavior.down,
        onTap: _handleTap,
        onSecondaryTapUp: (details) =>
            widget.onSecondaryTap(details.globalPosition),
        onPanStart: (details) => widget.onDragStart(
          details.globalPosition,
          GroupView._additivePressed,
        ),
        onPanUpdate: (details) => widget.onDragUpdate(details.globalPosition),
        onPanEnd: (_) => widget.onDragEnd(),
        onPanCancel: widget.onDragEnd,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: GroupView.handleHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(width: 6),
                const Icon(Icons.drag_indicator, size: 15, color: _ink),
                const SizedBox(width: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: GroupView.maxNameWidth,
                  ),
                  child: Text(
                    widget.group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                _ColorMenu(
                  selected: widget.group.color,
                  onPicked: widget.onColorPicked,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The fixed palette, as a menu of swatches.
///
/// A closed set rather than a colour wheel: the point of a group's colour is
/// telling two of them apart at a glance, and an arbitrary picker mostly
/// produces colours that are nearly the same as another one.
class _ColorMenu extends StatelessWidget {
  const _ColorMenu({required this.selected, required this.onPicked});

  final Color? selected;
  final ValueChanged<Color?> onPicked;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: <Widget>[
        MenuItemButton(
          leadingIcon: const _Swatch(color: NodeGroup.neutralColor),
          onPressed: () => onPicked(null),
          child: const Text('Neutral'),
        ),
        for (final swatch in NodeGroup.palette)
          MenuItemButton(
            leadingIcon: _Swatch(color: swatch),
            onPressed: () => onPicked(swatch),
            child: Text('#${swatch.toARGB32().toRadixString(16).substring(2)}'),
          ),
      ],
      builder: (context, menu, _) => InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.arrow_drop_down, size: 18, color: _ink),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: const Color(0x33000000)),
    ),
  );
}
