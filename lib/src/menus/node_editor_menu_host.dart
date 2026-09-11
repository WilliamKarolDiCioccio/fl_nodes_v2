import 'package:flutter/material.dart';

import 'node_menu_entry.dart';
import 'node_submenu_button.dart';

/// Renders [NodeMenuEntry] lists as a Material menu anchored to a point.
///
/// The anchor is a zero-sized box placed where the click landed, not the
/// canvas around it. That is deliberate and load-bearing: [MenuAnchor] wraps
/// its anchor in a `TapRegion` keyed to the menu, and a tap inside that region
/// is not an outside tap. Anchoring to the canvas would make every click
/// anywhere on it count as "inside", and the menu could then only be dismissed
/// with Escape.
///
/// Everything else — keyboard traversal, the app's [MenuTheme] — comes from
/// the Material widgets. Submenus are [NodeSubmenuButton], which is Material's
/// row over a panel that slides to stay on screen rather than flipping above
/// its row; see there for why.
class NodeEditorMenuHost extends StatefulWidget {
  const NodeEditorMenuHost({
    super.key,
    required this.controller,
    this.onClosed,
  });

  final MenuController controller;

  /// Called after the menu closes.
  ///
  /// The editor uses it to take focus back: its keyboard shortcuts are gated
  /// on the canvas holding primary focus, and an open menu takes it away, so
  /// without this Del and Ctrl+Z go quiet after the first right-click.
  final VoidCallback? onClosed;

  @override
  State<NodeEditorMenuHost> createState() => NodeEditorMenuHostState();
}

class NodeEditorMenuHostState extends State<NodeEditorMenuHost> {
  /// Focused while the menu is open.
  ///
  /// A menu anchored to a point has no button to focus, and the anchor's
  /// keyboard shortcuts only reach whatever is focused *inside* it — so
  /// without this the canvas keeps focus and the arrow keys never walk the
  /// menu.
  final FocusNode _anchorFocus = FocusNode(debugLabel: 'NodeEditorMenu');

  List<NodeMenuEntry> _entries = const <NodeMenuEntry>[];
  Offset _at = Offset.zero;
  CascadeSide _side = CascadeSide.right;

  @override
  void dispose() {
    _anchorFocus.dispose();
    super.dispose();
  }

  /// Opens [entries] at [position], in the coordinate space of the stack this
  /// host is a child of.
  ///
  /// Does nothing when there is nothing to show — a build hook that filters
  /// everything away should leave no empty popup behind — and says so, for a
  /// caller that has something to hold on screen only while a menu is up.
  bool open(List<NodeMenuEntry> entries, Offset position) {
    if (entries.isEmpty) return false;
    setState(() {
      _entries = entries;
      _at = position;
      _side = _sideFor(entries, position);
    });
    _anchorFocus.requestFocus();
    widget.controller.open();
    return true;
  }

  /// Which way the submenus should cascade from a menu opened at [position].
  ///
  /// Decided **once, for the whole tree, from its widest chain**, and handed
  /// down through [CascadeSide]. Each submenu deciding for itself — right
  /// when it fits, left when it does not — had the third level flip to the
  /// left of the second when it was the wider one, so a cascade zig-zagged
  /// across the screen and the deepest panel landed over the root. The widths
  /// are estimated from the labels with the menu's own text style rather than
  /// measured, because a panel is not laid out until it is opened; the
  /// estimate errs wide, and the panel's own layout still keeps it on screen
  /// whichever way it was told to go.
  CascadeSide _sideFor(List<NodeMenuEntry> entries, Offset position) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return CascadeSide.right;
    final style =
        MenuButtonTheme.of(context).style?.textStyle?.resolve(const {}) ??
        Theme.of(context).textTheme.labelLarge ??
        DefaultTextStyle.of(context).style;
    final origin = box.localToGlobal(position);
    final reach = origin.dx + estimateCascadeWidth(entries, style);
    // The same margin the panels keep when they are laid out.
    final room = MediaQuery.sizeOf(context).width - NodeSubmenuButton.margin;
    return reach <= room ? CascadeSide.right : CascadeSide.left;
  }

  void close() => widget.controller.close();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _at.dx,
      top: _at.dy,
      child: CascadeSide.provide(
        side: _side,
        child: MenuAnchor(
          controller: widget.controller,
          childFocusNode: _anchorFocus,
          // The click that dismisses is spent dismissing: it must not also land
          // on the canvas and move the selection out from under the menu.
          consumeOutsideTap: true,
          onClose: widget.onClosed,
          menuChildren: buildMenuChildren(_entries, autofocusFirst: true),
          child: Focus(focusNode: _anchorFocus, child: const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// How wide the widest chain of panels under [entries] is, root included.
///
/// A panel is as wide as its widest row; a chain is a panel plus the widest
/// chain under any of its submenus. The row arithmetic is Material's
/// `MenuItemButton` at M3 metrics — 12 of padding a side, a leading icon of
/// 24 with its gap, a trailing arrow of 24 with its gap, the shortcut's own
/// text — rounded up rather than down, since an estimate that ran short
/// would put a cascade on the side it cannot fit.
@visibleForTesting
double estimateCascadeWidth(List<NodeMenuEntry> entries, TextStyle style) {
  double textWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  var panel = 0.0;
  var deepest = 0.0;
  for (final entry in entries) {
    if (entry.isSeparator) continue;
    var row = 24 + textWidth(entry.label);
    if (entry.icon != null) row += 36;
    if (entry.isSubmenu) {
      row += 36;
      final below = estimateCascadeWidth(entry.children, style);
      if (below > deepest) deepest = below;
    } else if (entry.shortcut != null) {
      row += 24 + textWidth(entry.shortcut!.debugDescribeKeys());
    }
    if (row > panel) panel = row;
  }
  return panel + deepest;
}

/// Turns entries into Material menu widgets, recursively.
///
/// [autofocusFirst] focuses the first entry that can actually be chosen, which
/// is what puts the menu under the arrow keys. Only the top level does it: a
/// submenu opening on hover must not pull focus off the item the pointer is
/// on. Submenus are skipped — [SubmenuButton] cannot autofocus, and focusing
/// one would open it before anybody asked.
@visibleForTesting
List<Widget> buildMenuChildren(
  List<NodeMenuEntry> entries, {
  bool autofocusFirst = false,
}) {
  final first = autofocusFirst
      ? entries.firstWhere(
          (entry) => !entry.isSeparator && !entry.isSubmenu && entry.isEnabled,
          orElse: () => const NodeMenuEntry.separator(),
        )
      : null;

  return <Widget>[
    for (final entry in entries)
      if (entry.isSeparator)
        const Divider(height: 8)
      else if (entry.isSubmenu)
        // Not Material's SubmenuButton: its panel flips above the row when
        // the window runs out below, and a panel above its row is one the
        // pointer cannot reach without crossing the siblings that close it.
        NodeSubmenuButton(
          leadingIcon: entry.icon == null ? null : Icon(entry.icon, size: 18),
          menuChildren: buildMenuChildren(entry.children),
          child: Text(entry.label),
        )
      else
        MenuItemButton(
          autofocus: identical(entry, first),
          leadingIcon: entry.icon == null ? null : Icon(entry.icon, size: 18),
          shortcut: entry.shortcut,
          onPressed: entry.onSelected,
          child: Text(entry.label),
        ),
  ];
}
