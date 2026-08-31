import 'package:flutter/material.dart';

/// Shows a node's description, read-only.
///
/// A description belongs to a *kind* of node — it is written once, on the
/// prototype, by whoever wrote that prototype — so there is nothing here for
/// the app user to edit. It is the same modal shape as
/// `showConnectionLabelEditor` for the same reason: canvas-anchored prose
/// would have to be positioned, scaled and clipped along with everything else.
Future<void> showNodeDescription(
  BuildContext context, {
  required String description,
  String title = 'About this node',
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        // Selectable so a description can name a field or a key somebody
        // then wants to paste somewhere.
        child: SingleChildScrollView(child: SelectableText(description)),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
