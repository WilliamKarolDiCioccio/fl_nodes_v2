import 'package:flutter/material.dart';
import 'package:fl_nodes_v2/fl_nodes_v2.dart';

import 'form_node_body.dart';
import 'prototype_node_bodies.dart';
import 'prototype_nodes.dart';
import 'workflow_node.dart';

/// Per-type accent colour and icon.
@immutable
/// The one part of a node type's looks that is not on its prototype.
///
/// `label` and `icon` live on [NodePrototype] now, because the editor's own
/// Create and Description menus read them from the registry and two tables
/// that have to agree is one table too many. Colour stayed here: it is how
/// this demo paints a card, and the editor has no use for it.
class WorkflowStyle {
  const WorkflowStyle(this.color);

  final Color color;

  static const Map<WorkflowNodeType, WorkflowStyle> byType =
      <WorkflowNodeType, WorkflowStyle>{
        WorkflowNodeType.trigger: WorkflowStyle(Color(0xFF5BC48A)),
        WorkflowNodeType.action: WorkflowStyle(Color(0xFF6E97F0)),
        WorkflowNodeType.condition: WorkflowStyle(Color(0xFFE0A64A)),
        WorkflowNodeType.form: WorkflowStyle(Color(0xFF4FB6C4)),
        WorkflowNodeType.output: WorkflowStyle(Color(0xFFB57BD8)),
        WorkflowNodeType.format: WorkflowStyle(Color(0xFFE0716A)),
        WorkflowNodeType.fanOut: WorkflowStyle(Color(0xFF9AA65B)),
      };

  static WorkflowStyle of(WorkflowNodeType type) =>
      byType[type] ?? byType[WorkflowNodeType.action]!;

  /// The name and icon a node type publishes to the editor, read back so the
  /// card and the menus cannot disagree about either.
  static IconData iconOf(String type) =>
      workflowPrototypes[type]?.icon ?? Icons.play_arrow_rounded;

  static String labelOf(String type) => workflowPrototypes[type]?.label ?? type;
}

/// The body of a node.
///
/// This is the whole of what the demo has to supply to the editor: the canvas
/// handles dragging, selection, ports and wiring, and calls back here purely
/// to ask what the box looks like.
class WorkflowNodeCard extends StatelessWidget {
  const WorkflowNodeCard({
    super.key,
    required this.node,
    required this.state,
    required this.isDark,
    this.shadow = true,
  });

  final GraphNode node;
  final NodeRenderState state;
  final bool isDark;

  /// Whether to draw the blurred drop shadow.
  ///
  /// A knob for `bench.dart`: a blur is a separate GPU pass per card, and its
  /// cost is per-pixel, so it is the first thing to suspect when frame time
  /// scales with resolution rather than with the size of the graph.
  final bool shadow;

  /// How many card bodies have been built, for `benchmark/demo_benchmark.dart`.
  ///
  /// The editor reuses a node's widget when nothing about that node changed,
  /// and this is how the demo checks it is actually getting that.
  static int debugBuildCount = 0;

  @override
  Widget build(BuildContext context) {
    debugBuildCount++;
    final style = WorkflowStyle.of(node.workflowType);
    final surface = isDark ? const Color(0xFF232733) : Colors.white;
    final border = state.isConnectionTarget
        ? style.color
        : (state.isHovered
              ? (isDark ? const Color(0xFF454B5C) : const Color(0xFFC4CAD8))
              : (isDark ? const Color(0xFF32384A) : const Color(0xFFDDE1EA)));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        // Constant width: a thicker highlight border would reflow the card and
        // pull the anchored branch ports out of line with their rows.
        border: Border.all(color: border, width: CardMetrics.borderWidth),
        boxShadow: shadow
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: state.isDragging ? 0.35 : 0.18,
                  ),
                  blurRadius: state.isDragging ? 18 : 8,
                  offset: Offset(0, state.isDragging ? 8 : 3),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(
            style: style,
            type: node.type,
            title: node.title,
            isDark: isDark,
          ),
          switch (node.workflowType) {
            WorkflowNodeType.condition => _BranchList(
              branches: node.branches,
              isDark: isDark,
            ),
            WorkflowNodeType.form => FormNodeBody(node: node, isDark: isDark),
            WorkflowNodeType.format => FormatNodeBody(
              node: node,
              isDark: isDark,
            ),
            WorkflowNodeType.fanOut => FanOutNodeBody(
              node: node,
              isDark: isDark,
            ),
            _ => _Body(subtitle: node.subtitle, isDark: isDark),
          },
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.style,
    required this.type,
    required this.title,
    required this.isDark,
  });

  final WorkflowStyle style;
  final String type;
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: CardMetrics.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: <Widget>[
          Icon(WorkflowStyle.iconOf(type), size: 15, color: style.color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFFE6E9F0)
                    : const Color(0xFF1E2230),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.subtitle, required this.isDark});

  final String? subtitle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    if (subtitle == null || subtitle.isEmpty) {
      return const SizedBox(height: CardMetrics.bodyPadding);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.35,
          color: isDark ? const Color(0xFF98A0B4) : const Color(0xFF5C6478),
        ),
      ),
    );
  }
}

/// One row per branch, each lining up with its anchored output port.
class _BranchList extends StatelessWidget {
  const _BranchList({required this.branches, required this.isDark});

  final List<String> branches;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CardMetrics.bodyPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final branch in branches)
            SizedBox(
              height: CardMetrics.rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    branch,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? const Color(0xFFA8B0C4)
                          : const Color(0xFF5C6478),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
