import 'package:flutter/material.dart';

/// One row of a context menu.
///
/// Entries are data rather than widgets so that what a menu offers — and what
/// it offers greyed out — can be asserted without pumping a menu and
/// dismissing it. It also gives a host something to inspect: the build hook
/// receives the defaults and can filter or reorder them instead of having to
/// rebuild the whole menu to change one line.
@immutable
class NodeMenuEntry {
  const NodeMenuEntry({
    required this.label,
    this.icon,
    this.shortcut,
    this.onSelected,
    this.children = const <NodeMenuEntry>[],
  }) : _separator = false;

  /// A rule between two groups of entries.
  ///
  /// Leading, trailing and doubled separators are dropped when the menu is
  /// built, so a hook that removes the last entry of a group does not leave a
  /// rule hanging under nothing.
  const NodeMenuEntry.separator()
    : label = '',
      icon = null,
      shortcut = null,
      onSelected = null,
      children = const <NodeMenuEntry>[],
      _separator = true;

  final String label;
  final IconData? icon;

  /// Rendered as a hint. It does not bind anything — the editor's own
  /// shortcuts already do, and a menu that claimed a key it did not own would
  /// be lying.
  final MenuSerializableShortcut? shortcut;

  /// Null renders the entry disabled, which is the point: an action that does
  /// not apply right now should still say it exists.
  final VoidCallback? onSelected;

  /// Non-empty turns this into a submenu, and [onSelected] is then ignored.
  final List<NodeMenuEntry> children;

  final bool _separator;

  bool get isSeparator => _separator;
  bool get isSubmenu => children.isNotEmpty;

  /// A submenu is enabled when anything inside it is, however deep.
  bool get isEnabled =>
      isSubmenu ? children.any((child) => child.isEnabled) : onSelected != null;

  NodeMenuEntry copyWith({
    String? label,
    IconData? icon,
    MenuSerializableShortcut? shortcut,
    VoidCallback? onSelected,
    List<NodeMenuEntry>? children,
  }) => _separator
      ? this
      : NodeMenuEntry(
          label: label ?? this.label,
          icon: icon ?? this.icon,
          shortcut: shortcut ?? this.shortcut,
          onSelected: onSelected ?? this.onSelected,
          children: children ?? this.children,
        );

  /// Drops separators that would render against nothing.
  ///
  /// Menus are assembled from parts that come and go — a description a
  /// prototype may not declare, a project submenu a host may switch off — so
  /// tidying at the end is simpler than every builder having to know what its
  /// neighbours decided.
  static List<NodeMenuEntry> tidy(List<NodeMenuEntry> entries) {
    final out = <NodeMenuEntry>[];
    for (final entry in entries) {
      if (entry.isSeparator && (out.isEmpty || out.last.isSeparator)) continue;
      out.add(entry);
    }
    while (out.isNotEmpty && out.last.isSeparator) {
      out.removeLast();
    }
    return out;
  }

  @override
  String toString() => _separator
      ? 'NodeMenuEntry.separator()'
      : 'NodeMenuEntry($label'
            '${isSubmenu ? ', ${children.length} children' : ''}'
            '${isEnabled ? '' : ', disabled'})';
}
