import 'package:flutter/material.dart';

/// Shows a node's description, read-only.
///
/// A description belongs to a *kind* of node — it is written once, on the
/// prototype, by whoever wrote that prototype — so there is nothing here for
/// the app user to edit. It is the same modal shape as
/// `showConnectionLabelEditor` for the same reason: canvas-anchored prose
/// would have to be positioned, scaled and clipped along with everything else.
///
/// [builder] is how a host that writes its descriptions in something —
/// Markdown, most likely — renders them; see `NodeEditor.descriptionBuilder`
/// for why the package does not decide that. Null falls back to selectable
/// plain text, which is what a description written as prose wants anyway.
Future<void> showNodeDescription(
  BuildContext context, {
  required String description,
  String title = 'About this node',
  Widget Function(BuildContext context, String description)? builder,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          // Selectable so a description can name a field or a key somebody
          // then wants to paste somewhere. A [builder]'s widget is the host's
          // to make selectable; most Markdown bodies already are.
          child:
              builder?.call(context, description) ??
              SelectableText(description),
        ),
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
