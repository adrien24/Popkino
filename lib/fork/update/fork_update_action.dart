// FORK: bouton-mise-a-jour — home app bar button announcing a sideload update.
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_action_bar.dart';
import '../../i18n/strings.g.dart';
import '../../widgets/app_icon.dart';
import 'fork_update_controller.dart';
import 'fork_update_dialog.dart';
import 'sideload_flags.dart';

const _slotLabel = 'fork_update';

/// Fixed-slot action: when hidden it keeps its `debugLabel`, `onPressed: null`
/// and an empty child, so the bar never recreates the focus nodes of its
/// neighbours (changing the actions length would lose the focus).
FocusableAction _emptyAction() =>
    const FocusableAction(debugLabel: _slotLabel, onPressed: null, child: SizedBox.shrink());

FocusableAction forkUpdateAction(BuildContext context, {required Color iconColor}) {
  if (!ForkSideload.isSupported) return _emptyAction();

  final c = context.watch<ForkUpdateController?>();
  c?.ensureChecked();

  final pending = c?.pendingInstall;
  if (c != null && pending != null && !c.resumeConsumed) {
    c.resumeConsumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        showForkUpdateDialog(context, pending: pending);
      } else {
        // Not shown (covered route, unmounted): retry on the next rebuild.
        c.resumeConsumed = false;
      }
    });
  }

  final release = c?.available;
  if (c == null || release == null) return _emptyAction();

  void open() => showForkUpdateDialog(context, release: release);

  return FocusableAction(
    debugLabel: _slotLabel,
    onPressed: open,
    builder: (context, state) => _ForkUpdateButton(showFocus: state.showFocus, iconColor: iconColor, onPressed: open),
  );
}

class _ForkUpdateButton extends StatefulWidget {
  const _ForkUpdateButton({required this.showFocus, required this.iconColor, required this.onPressed});

  final bool showFocus;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  State<_ForkUpdateButton> createState() => _ForkUpdateButtonState();
}

class _ForkUpdateButtonState extends State<_ForkUpdateButton> {
  final _label = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    _syncLabel();
  }

  @override
  void didUpdateWidget(_ForkUpdateButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showFocus != widget.showFocus) _syncLabel();
  }

  void _syncLabel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.showFocus) {
        _label.show();
      } else {
        _label.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OverlayPortal(
      controller: _label,
      // The overlay hands its child tight, screen-sized constraints and the
      // follower passes them through. The Align loosens them so the follower
      // is sized by the label; its anchors then centre it under the button.
      overlayChildBuilder: (context) => Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 4),
          child: IgnorePointer(
            // Bounded width keeps the label on screen for a button in the bar.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    t.fork.update.buttonLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Container(
          decoration: FocusTheme.focusBackgroundDecoration(context, isFocused: widget.showFocus, borderRadius: 20),
          child: Stack(
            children: [
              IconButton(
                icon: AppIcon(Symbols.system_update_rounded, color: widget.iconColor),
                onPressed: widget.onPressed,
                tooltip: t.fork.update.buttonLabel,
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('fork_update_badge'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
