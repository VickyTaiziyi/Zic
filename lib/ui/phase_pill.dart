import 'package:flutter/material.dart';

import 'theme.dart';

/// Status pill shared by the task list rows and the chat turn footers.
///
/// Zic style: a tinted surface (never a loud solid) + a small status dot
/// carrying the hue + the label. Running phases get a spinner dot. Colors
/// come from the phase-pill tokens so light/dark stay balanced.
class PhasePill extends StatelessWidget {
  final String label;
  final String phase;

  /// Task-list style: tighter padding, 10px label.
  final bool solid;

  const PhasePill({
    super.key,
    required this.label,
    required this.phase,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final running = phase == 'running' || phase == 'prewarming';
    final failed = phase == 'error' || phase == 'failed';
    final done = phase == 'completedSuccess';

    final (bg, fg, icon) = dark
        ? switch (phase) {
            'running' || 'prewarming' => (
                ZColors.pillRunningBgDark,
                ZColors.pillRunningFgDark,
                Icons.autorenew
              ),
            'completedSuccess' => (
                ZColors.pillSuccessBgDark,
                ZColors.pillSuccessFgDark,
                Icons.check
              ),
            'error' || 'failed' => (
                ZColors.pillFailedBgDark,
                ZColors.pillFailedFgDark,
                Icons.error_outline
              ),
            'completedInterrupted' => (
                ZColors.pillIdleBgDark,
                ZColors.pillIdleFgDark,
                Icons.remove_circle_outline
              ),
            _ => (
                ZColors.pillIdleBgDark,
                ZColors.pillIdleFgDark,
                Icons.circle_outlined
              ),
          }
        : switch (phase) {
            'running' || 'prewarming' => (
                ZColors.pillRunningBg,
                ZColors.pillRunningFg,
                Icons.autorenew
              ),
            'completedSuccess' => (
                ZColors.pillSuccessBg,
                ZColors.pillSuccessFg,
                Icons.check
              ),
            'error' || 'failed' => (
                ZColors.pillFailedBg,
                ZColors.pillFailedFg,
                Icons.error_outline
              ),
            'completedInterrupted' => (
                ZColors.pillIdleBg,
                ZColors.pillIdleFg,
                Icons.remove_circle_outline
              ),
            _ => (
                ZColors.pillIdleBg,
                ZColors.pillIdleFg,
                Icons.circle_outlined
              ),
          };

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: solid ? 7 : 8, vertical: solid ? 2.5 : 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            )
          else if (done || failed)
            Icon(icon, size: 10, color: fg)
          else
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: TextStyle(
              fontSize: solid ? 10 : 10.5,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
