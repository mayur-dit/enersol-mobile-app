import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The screen's name, as the page's own heading.
///
/// WHERE THE HEADER'S CAPTION USED TO BE. [AppHeader] carried the name on a
/// second line under the wordmark, set small, centred and all-caps; it sat low
/// and detached — 16 logical pixels below the logo, 7 above the hairline — and
/// read as a label stuck on the brand bar rather than as the title of what you
/// were looking at. Here it is the first line of the page: left-aligned on the
/// same [AppSpacing.page] margin as everything that scrolls beneath it, at a
/// size you read rather than squint at.
///
/// NOT ON HOME. Home opens with the greeting and the customer's own name, which
/// is already its heading; a "Home" above that would be a caption on a caption.
/// The shell passes null for that tab and this widget is simply not built.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key, this.trailing});

  final String text;

  /// An action belonging to the page as a whole, parked on the heading's line
  /// rather than given a row of its own.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
