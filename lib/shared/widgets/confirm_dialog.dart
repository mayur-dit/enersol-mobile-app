import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Ask a yes/no question, laid out the same way everywhere.
///
/// The buttons are laid out BY HAND rather than through `actions:`, which
/// stacks them vertically as soon as the labels are wide enough — that put
/// Cancel in an odd place at large text scales. Two equal halves keep the pair
/// predictable at any scale.
///
/// Returns false when the sheet is dismissed by tapping outside, so a caller
/// can treat "no answer" as "no".
Future<bool> confirmAction(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  required String confirmLabel,
  Color confirmColor = AppColors.ember,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon, color: confirmColor, size: 34),
      title: Text(title),
      content: Text(message, textAlign: TextAlign.center),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: confirmColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  return ok == true;
}

/// The one back press the app cannot undo: back on the landing screen.
///
/// Asks first, then closes the app. Guarded to Android because it is the only
/// platform with a back button to reach this from — iOS has no back gesture on
/// a root route, and Apple treats an app that quits itself as a defect.
Future<void> confirmExit(BuildContext context) async {
  final leave = await confirmAction(
    context,
    icon: Icons.exit_to_app_rounded,
    title: 'Exit Enersol?',
    message: 'You are on the home screen. Close the app?',
    cancelLabel: 'Stay',
    confirmLabel: 'Exit',
  );

  if (!leave) return;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await SystemNavigator.pop();
}
