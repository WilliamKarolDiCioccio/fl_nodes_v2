import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A submenu entry whose panel **slides** to stay on screen rather than
/// flipping above its button.
///
/// Material's [SubmenuButton] lays its panel out with the same delegate a
/// menu bar uses: a panel that would run off the bottom of the window is
/// moved to end at the *top* of the button whenever it fits there. For a
/// menu bar that is right. For a cascade opened at a click point it is not:
/// the panel now sits entirely above the row that opened it, and the
/// pointer's path up to it crosses the sibling rows — each of which takes
/// focus on hover and closes the open child. Near the bottom of the window a
/// three-level Create menu became unreachable by mouse.
///
/// This keeps everything else Material's: the row is a [MenuItemButton], the
/// entries inside are whatever the caller builds, the parent/child linkage is
/// [RawMenuAnchor]'s own — so a click elsewhere, Escape and choosing an item
/// still close the whole tree — and the panel is dressed from [MenuTheme].
/// What it owns is the placement: to the right of the row, top-aligned with
/// it, pushed up only as far as the window demands and never over the row.
class NodeSubmenuButton extends StatefulWidget {
  const NodeSubmenuButton({
    super.key,
    required this.child,
    required this.menuChildren,
    this.leadingIcon,
  });

  final Widget child;
  final Widget? leadingIcon;
  final List<Widget> menuChildren;

  /// On the panel's [Material], so a test can measure where one landed.
  @visibleForTesting
  static const Key panelKey = ValueKey<String>('NodeSubmenuButton.panel');

  @override
  State<NodeSubmenuButton> createState() => _NodeSubmenuButtonState();
}

class _NodeSubmenuButtonState extends State<NodeSubmenuButton> {
  final MenuController _controller = MenuController();
  final FocusNode _buttonFocus = FocusNode(debugLabel: 'NodeSubmenuButton');
  final FocusScopeNode _panelScope = FocusScopeNode(
    debugLabel: 'NodeSubmenuPanel',
  );

  @override
  void initState() {
    super.initState();
    _buttonFocus.addListener(_handleButtonFocus);
  }

  @override
  void dispose() {
    _buttonFocus
      ..removeListener(_handleButtonFocus)
      ..dispose();
    _panelScope.dispose();
    super.dispose();
  }

  /// Set by a hover and spent by the focus that follows it; see [_hover].
  bool _openOnFocus = false;

  /// The rule that closes a submenu when the pointer moves to a sibling row,
  /// and keeps it open while the pointer is inside its own panel.
  ///
  /// A sibling [MenuItemButton] takes focus on hover; when that pulls focus
  /// off this row and the panel does not hold it either, the panel goes.
  /// Focus moving *into* the panel is the other case and must not close it.
  void _handleButtonFocus() {
    if (_buttonFocus.hasPrimaryFocus) {
      if (_openOnFocus) {
        _openOnFocus = false;
        _open();
      }
      return;
    }
    if (_controller.isOpen && !_panelScope.hasFocus) _controller.close();
  }

  /// Opens on hover — but only once the focus the hover brings has landed.
  ///
  /// [MenuItemButton] reports the hover *before* it takes focus, and taking
  /// focus is what makes the row the pointer just left close its children —
  /// which, opened here and now, would include this panel. So the hover asks
  /// for the panel and the focus change delivers it, a frame of ordering
  /// that Material's own submenu settles by reopening on focus instead.
  void _hover(bool hovered) {
    if (!hovered) return;
    if (_buttonFocus.hasPrimaryFocus) {
      _open();
    } else {
      _openOnFocus = true;
    }
  }

  void _open() {
    if (!_controller.isOpen) _controller.open();
  }

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _open();
    }
  }

  /// Opens and puts the keyboard on the first entry, for the right arrow.
  void _openAndFocusFirst() {
    _open();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.isOpen) _panelScope.nextFocus();
    }, debugLabel: 'NodeSubmenuButton.focusFirst');
  }

  /// Closes and hands the keyboard back to the row, for the left arrow.
  void _closeToButton() {
    _controller.close();
    _buttonFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.menuChildren.isNotEmpty;
    return RawMenuAnchor(
      controller: _controller,
      childFocusNode: _buttonFocus,
      overlayBuilder: _buildPanel,
      child: Actions(
        actions: <Type, Action<Intent>>{
          DirectionalFocusIntent: _RowDirectionalAction(this),
        },
        child: MenuItemButton(
          focusNode: _buttonFocus,
          leadingIcon: widget.leadingIcon,
          trailingIcon: const Icon(Icons.arrow_right, size: 24),
          // Pressing the row opens the panel; it must not close the tree the
          // way choosing an entry does.
          closeOnActivate: false,
          onPressed: enabled ? _toggle : null,
          onHover: enabled ? _hover : null,
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, RawMenuOverlayInfo info) {
    final theme = MenuTheme.of(context).style;
    final scheme = Theme.of(context).colorScheme;
    T? resolve<T>(WidgetStateProperty<T?>? Function(MenuStyle) pick) =>
        theme == null ? null : pick(theme)?.resolve(const <WidgetState>{});

    // Material 3's own defaults, for whatever the theme leaves unsaid.
    final background =
        resolve((s) => s.backgroundColor) ?? scheme.surfaceContainer;
    final elevation = resolve((s) => s.elevation) ?? 3.0;
    final shape =
        resolve((s) => s.shape) ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        );
    final padding =
        resolve((s) => s.padding)?.resolve(Directionality.of(context)) ??
        const EdgeInsets.symmetric(vertical: 8);

    return ConstrainedBox(
      constraints: BoxConstraints.loose(info.overlaySize),
      child: CustomSingleChildLayout(
        delegate: _SlidingSubmenuLayout(
          anchor: info.anchorRect,
          // So the first entry lines up with the row that opened it, the way
          // Material offsets its own submenus by their padding.
          rise: padding.top,
        ),
        child: TapRegion(
          // The root's group: a tap inside this panel is not a tap outside
          // the menu, or the whole tree would close on choosing an entry.
          groupId: info.tapRegionGroupId,
          child: Actions(
            actions: <Type, Action<Intent>>{
              DirectionalFocusIntent: _PanelDirectionalAction(this),
            },
            child: FocusScope(
              node: _panelScope,
              child: Material(
                key: NodeSubmenuButton.panelKey,
                elevation: elevation,
                shape: shape,
                color: background,
                surfaceTintColor: resolve((s) => s.surfaceTintColor),
                shadowColor: resolve((s) => s.shadowColor),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: padding,
                  child: IntrinsicWidth(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: widget.menuChildren,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right on the row opens the panel and walks in. Left is handed **up**: a
/// row that is itself inside a submenu's panel must let that panel close,
/// and the default action would instead walk focus geometrically to whatever
/// sits to the left — the parent row, typically — and leave the panel open.
class _RowDirectionalAction extends DirectionalFocusAction {
  _RowDirectionalAction(this.state);

  final _NodeSubmenuButtonState state;

  @override
  void invoke(DirectionalFocusIntent intent) {
    switch (intent.direction) {
      case TraversalDirection.right when state.widget.menuChildren.isNotEmpty:
        state._openAndFocusFirst();
      case TraversalDirection.left:
        // From the row's own context, so the lookup starts above the row's
        // Actions and finds the enclosing panel's — or nothing, at the top.
        if (Actions.maybeFind<DirectionalFocusIntent>(state.context) != null) {
          Actions.invoke(state.context, intent);
        } else {
          super.invoke(intent);
        }
      default:
        super.invoke(intent);
    }
  }
}

/// Left inside the panel closes it and hands the keyboard back to the row.
/// Up and down stay within the panel: the scope keeps them from walking out
/// into the parent menu.
class _PanelDirectionalAction extends DirectionalFocusAction {
  _PanelDirectionalAction(this.state);

  final _NodeSubmenuButtonState state;

  @override
  void invoke(DirectionalFocusIntent intent) {
    if (intent.direction == TraversalDirection.left) {
      state._closeToButton();
      return;
    }
    super.invoke(intent);
  }
}

/// Beside the row, top-aligned, and pushed only as far as the window needs.
///
/// Horizontally the panel goes to the right of the row and flips to the left
/// when there is no room — a flip sideways keeps the panel touching the row,
/// which is what makes it reachable. Vertically it never flips: a panel that
/// would run off the bottom is slid up until it fits, and one taller than the
/// window is pinned to the top. Both keep the panel overlapping the row's
/// band, so the pointer can leave the row sideways and be on the panel.
class _SlidingSubmenuLayout extends SingleChildLayoutDelegate {
  const _SlidingSubmenuLayout({required this.anchor, required this.rise});

  /// The row that opened the panel, in the overlay's coordinates.
  final Rect anchor;

  /// How far above the row's top the panel's top sits, so the padding does
  /// not push the first entry below the row.
  final double rise;

  /// Kept clear of the window's edge, as Material keeps its own menus.
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        constraints.biggest,
      ).deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.right;
    if (x + childSize.width > size.width - _margin) {
      final left = anchor.left - childSize.width;
      x = left >= _margin ? left : size.width - _margin - childSize.width;
    }

    var y = anchor.top - rise;
    final bottom = size.height - _margin;
    if (y + childSize.height > bottom) y = bottom - childSize.height;
    y = math.max(y, _margin);

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_SlidingSubmenuLayout old) =>
      old.anchor != anchor || old.rise != rise;
}
