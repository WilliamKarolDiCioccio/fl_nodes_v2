import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lays out a node's content and reports the size it settled on.
///
/// Deliberately unbounded: the content decides its own extent, which is what
/// lets a node grow with its body. The measured size goes back to the editor
/// through [onContentSized] so connection endpoints and port handles follow.
///
/// This used to carry the port handles as extra children, with a transparent
/// ring of padding around the content so a handle straddling the border stayed
/// inside the box and therefore hittable. Handles are painted now and picked
/// from the spatial index, so both the ring and the multi-child machinery are
/// gone — and a node's box is exactly its content again.
class NodeBox extends SingleChildRenderObjectWidget {
  const NodeBox({
    super.key,
    required this.onContentSized,
    required Widget child,
  }) : super(child: child);

  /// Called after layout whenever the content's size changes.
  final ValueChanged<Size> onContentSized;

  @override
  RenderNodeBox createRenderObject(BuildContext context) =>
      RenderNodeBox(onContentSized: onContentSized);

  @override
  void updateRenderObject(BuildContext context, RenderNodeBox renderObject) {
    renderObject.onContentSized = onContentSized;
  }
}

class RenderNodeBox extends RenderProxyBox {
  RenderNodeBox({required ValueChanged<Size> onContentSized})
    : _onContentSized = onContentSized;

  ValueChanged<Size> _onContentSized;
  set onContentSized(ValueChanged<Size> value) => _onContentSized = value;

  Size? _reportedSize;

  @override
  void performLayout() {
    final content = child;
    if (content == null) {
      size = constraints.smallest;
      return;
    }
    content.layout(const BoxConstraints(), parentUsesSize: true);
    size = constraints.constrain(content.size);
    _reportContentSize(content.size);
  }

  /// Reported after the frame: notifying listeners mid-layout would rebuild
  /// widgets that are already laid out.
  void _reportContentSize(Size contentSize) {
    if (_reportedSize == contentSize) return;
    _reportedSize = contentSize;
    final callback = _onContentSized;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!attached) return;
      callback(contentSize);
    });
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final content = child;
    if (content == null) return constraints.smallest;
    return constraints.constrain(content.getDryLayout(const BoxConstraints()));
  }
}
