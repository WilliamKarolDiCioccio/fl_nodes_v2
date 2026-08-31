import 'package:flutter/material.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

/// The kind of link a condition's branch emits.
///
/// Its caption belongs to the app user: tap the text on the wire to name the
/// choice it stands for.
const String branchLinkType = 'branch';

/// The kind of link a fan-out exit emits.
///
/// Its caption is derived from the port it leaves, so it follows along when
/// the exits renumber and can never be edited by hand.
const String exitLinkType = 'exit';

/// The node kinds this demo knows how to draw.
enum WorkflowNodeType {
  trigger,
  action,
  condition,
  form,
  output,
  format,
  fanOut,
}

/// Fixed metrics for the condition card.
///
/// A branch's output port has to line up with its row, so the card's geometry
/// is computed rather than measured: the height is declared up front and each
/// port is anchored at its row's centre.
abstract final class CardMetrics {
  static const double width = 224;
  static const double headerHeight = 38;
  static const double rowHeight = 30;
  static const double bodyPadding = 10;

  /// The card's border sits inside its box, so it counts towards the height
  /// and shifts every row down by one pixel.
  static const double borderWidth = 1;

  /// Height of a card whose body is a stack of [rows] plain rows.
  static double rowsHeight(int rows) =>
      borderWidth * 2 + headerHeight + bodyPadding * 2 + rowHeight * rows;

  /// Centre of row [index], as a fraction of a [rows]-row card's height.
  static double rowAnchorY(int index, int rows) {
    final y =
        borderWidth +
        headerHeight +
        bodyPadding +
        rowHeight * index +
        rowHeight / 2;
    return y / rowsHeight(rows);
  }

  /// Centre of the header, as a fraction of a [rows]-row card's height.
  static double headerRowAnchorY(int rows) =>
      (borderWidth + headerHeight / 2) / rowsHeight(rows);

  static double conditionHeight(int branches) => rowsHeight(branches);

  static double branchAnchorY(int index, int branches) =>
      rowAnchorY(index, branches);

  static double headerAnchorY(int branches) => headerRowAnchorY(branches);

  /// The format card puts a text field above its argument rows.
  static const double fieldRowHeight = 44;

  static double formatHeight(int args) => rowsHeight(args) + fieldRowHeight;

  static double formatArgAnchorY(int index, int args) {
    final y =
        borderWidth +
        headerHeight +
        bodyPadding +
        fieldRowHeight +
        rowHeight * index +
        rowHeight / 2;
    return y / formatHeight(args);
  }

  static double formatHeaderAnchorY(int args) =>
      (borderWidth + headerHeight / 2) / formatHeight(args);
}

/// Factory helpers building the demo's node shapes.
abstract final class WorkflowNodes {
  static GraphNode trigger({
    required String id,
    required Offset position,
    required String title,
    String? subtitle,
  }) {
    return GraphNode(
      id: id,
      type: WorkflowNodeType.trigger.name,
      position: position,
      width: CardMetrics.width,
      data: <String, Object?>{'title': title, 'subtitle': subtitle},
      ports: const <NodePort>[
        NodePort.output(id: 'out', kind: PortKind.control),
      ],
    );
  }

  static GraphNode action({
    required String id,
    required Offset position,
    required String title,
    String? subtitle,
  }) {
    return GraphNode(
      id: id,
      type: WorkflowNodeType.action.name,
      position: position,
      width: CardMetrics.width,
      // No height: the card sizes to its text and the editor measures it.
      data: <String, Object?>{'title': title, 'subtitle': subtitle},
      ports: const <NodePort>[
        NodePort.input(id: 'in', kind: PortKind.control),
        NodePort.output(id: 'out', kind: PortKind.control),
      ],
    );
  }

  static GraphNode output({
    required String id,
    required Offset position,
    required String title,
    String? subtitle,
  }) {
    return GraphNode(
      id: id,
      type: WorkflowNodeType.output.name,
      position: position,
      width: CardMetrics.width,
      data: <String, Object?>{'title': title, 'subtitle': subtitle},
      ports: const <NodePort>[
        NodePort.input(id: 'in', kind: PortKind.control, maxConnections: null),
        // The one data input in the hand-authored half of the demo: whatever
        // reaches it is what this node would print.
        NodePort.input(id: 'value', label: 'value', dataType: 'string'),
      ],
    );
  }

  /// A node whose body is an ordinary Flutter form.
  ///
  /// Auto-height, so it grows as its text field wraps; the ports follow the
  /// measured size.
  static GraphNode form({
    required String id,
    required Offset position,
    required String title,
    String subject = '',
    bool sendAsHtml = false,
    double delayMinutes = 0,
    Color labelColor = const Color(0xFF6E97F0),
  }) {
    return GraphNode(
      id: id,
      type: WorkflowNodeType.form.name,
      position: position,
      width: 272,
      data: <String, Object?>{
        'title': title,
        'subject': subject,
        'sendAsHtml': sendAsHtml,
        'delayMinutes': delayMinutes,
        'labelColor': labelColor.toARGB32(),
      },
      ports: const <NodePort>[
        NodePort.input(id: 'in', kind: PortKind.control),
        NodePort.output(id: 'out', kind: PortKind.control),
      ],
    );
  }

  /// Fields only: `conditionPrototype` derives the ports and the height from
  /// `branches`, and having the row maths in two places is exactly how the
  /// ports and the rows they are supposed to line up with drift apart.
  static GraphNode condition({
    required String id,
    required Offset position,
    required String title,
    required List<String> branches,
  }) {
    return GraphNode(
      id: id,
      type: WorkflowNodeType.condition.name,
      position: position,
      width: CardMetrics.width,
      data: <String, Object?>{'title': title, 'branches': branches},
    );
  }
}

/// Reads the demo's payload conventions off a node.
extension WorkflowNodeData on GraphNode {
  WorkflowNodeType get workflowType => WorkflowNodeType.values.firstWhere(
    (candidate) => candidate.name == type,
    orElse: () => WorkflowNodeType.action,
  );

  String get title => (data['title'] as String?) ?? 'Untitled';
  String? get subtitle => data['subtitle'] as String?;
  List<String> get branches =>
      (data['branches'] as List<Object?>? ?? const <Object?>[]).cast<String>();

  // Form fields. Everything is stored as a JSON-friendly primitive so the
  // graph stays serialisable.
  String get subject => (data['subject'] as String?) ?? '';
  bool get sendAsHtml => (data['sendAsHtml'] as bool?) ?? false;
  double get delayMinutes => (data['delayMinutes'] as num?)?.toDouble() ?? 0;
  Color get labelColor => Color((data['labelColor'] as int?) ?? 0xFF6E97F0);

  /// The format node's template string.
  String get formatText => (data['format'] as String?) ?? '';
}
