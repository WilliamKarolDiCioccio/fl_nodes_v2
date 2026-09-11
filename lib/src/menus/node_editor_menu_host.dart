import 'package:flutter/material.dart';

import 'node_menu_entry.dart';

/// Renders [NodeMenuEntry] lists as a Material menu anchored to a point.
///
/// The anchor is a zero-sized box placed where the click landed, not the
/// canvas around it. That is deliberate and load-bearing: [MenuAnchor] wraps
/// its anchor in a `TapRegion` keyed to the menu, and a tap inside that region
/// is not an outside tap. Anchoring to the canvas would make every click
/// anywhere on it count as "inside", and the menu could then only be dismissed
/// with Escape.
///
/// Everything else — submenus, keyboard traversal, the app's [MenuTheme] —
/// comes from the Material widgets.
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
    });
    _anchorFocus.requestFocus();
    widget.controller.open();
    return true;
  }

  void close() => widget.controller.close();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _at.dx,
      top: _at.dy,
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
    );
  }
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
        SubmenuButton(
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
