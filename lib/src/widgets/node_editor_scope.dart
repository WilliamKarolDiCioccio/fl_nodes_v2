import 'package:flutter/widgets.dart';

import '../controller/node_editor_controller.dart';
import '../theme/node_editor_theme.dart';

/// Exposes the editor's controller and theme to node bodies built below it.
///
/// Lets a custom node widget act on the graph — rename itself, add a choice,
/// delete a branch — without the host threading callbacks through by hand.
class NodeEditorScope extends InheritedWidget {
  const NodeEditorScope({
    super.key,
    required this.controller,
    required this.theme,
    required super.child,
  });

  final NodeEditorController controller;
  final NodeEditorTheme theme;

  static NodeEditorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NodeEditorScope>();

  static NodeEditorScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No NodeEditorScope found in the widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(NodeEditorScope oldWidget) =>
      oldWidget.controller != controller || oldWidget.theme != theme;
}
