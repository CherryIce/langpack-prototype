import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A compact, keyboard-aware shell for form routes shown as modal popups.
///
/// The caller owns the route and its state. In particular, callers can disable
/// barrier dismissal while [busy] and wait for route completion before disposing
/// controllers used by [child].
class IosFormSheet extends StatelessWidget {
  const IosFormSheet({
    super.key,
    required this.title,
    required this.cancelLabel,
    required this.doneLabel,
    required this.child,
    this.onCancel,
    this.onDone,
    this.busy = false,
    this.showCancel = true,
  });

  final String title;
  final String cancelLabel;
  final String doneLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onDone;
  final bool busy;
  final bool showCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final maxHeight = math.max(
      0.0,
      media.size.height - keyboardInset - media.padding.top - 8,
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: Material(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => _SheetHeader(
                        title: title,
                        cancelLabel: cancelLabel,
                        doneLabel: doneLabel,
                        onCancel: busy ? null : onCancel,
                        onDone: busy ? null : onDone,
                        showCancel: showCancel,
                        narrow:
                            constraints.maxWidth < 360 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.2,
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: Material(
                          color: Colors.transparent,
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.cancelLabel,
    required this.doneLabel,
    required this.onCancel,
    required this.onDone,
    required this.showCancel,
    required this.narrow,
  });

  final String title;
  final String cancelLabel;
  final String doneLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onDone;
  final bool showCancel;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final cancel = showCancel ? _action(cancelLabel, onCancel) : null;
    final done = _action(doneLabel, onDone, strong: true);
    final heading = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: narrow
          ? Column(
              children: [
                Row(
                  children: [if (cancel != null) cancel, const Spacer(), done],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: heading,
                ),
                const SizedBox(height: 7),
              ],
            )
          : Row(
              children: [
                if (cancel != null) ...[cancel, const SizedBox(width: 6)],
                Expanded(child: heading),
                const SizedBox(width: 6),
                done,
              ],
            ),
    );
  }

  Widget _action(String label, VoidCallback? callback, {bool strong = false}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 44,
          maxWidth: 150,
          minHeight: 44,
        ),
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: callback,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
}

/// Keeps wide-screen confirmations Material while using iOS controls on mobile.
Future<bool?> showAdaptiveConfirmation({
  required BuildContext context,
  required bool compact,
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  bool destructive = false,
}) {
  if (compact) {
    return showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
