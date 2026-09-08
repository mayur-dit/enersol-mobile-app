import 'package:enersol_customer/shared/widgets/app_drawer.dart';
import 'package:enersol_customer/shared/widgets/app_header.dart';
import 'package:enersol_customer/shared/widgets/page_scaffold.dart';
import 'package:enersol_customer/shared/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The shared panels, and the scroll behaviour six screens depended on.
void main() {
  setUpAll(useOfflineFonts);

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  group('EmptyState', () {
    testWidgets('is scrollable, so pull-to-refresh works over it', (
      tester,
    ) async {
      await pump(
        tester,
        const EmptyState(icon: Icons.inbox, title: 'Nothing here'),
      );
      // A bare Center is not a scroll container, which is why a
      // RefreshIndicator wrapped around one had nothing to listen to and the
      // gesture was silently dead on every empty screen.
      expect(find.byType(Scrollable), findsOneWidget);
    });

    testWidgets('can actually be pulled', (tester) async {
      var refreshed = false;
      await pump(
        tester,
        RefreshIndicator(
          onRefresh: () async => refreshed = true,
          child: const EmptyState(icon: Icons.inbox, title: 'Nothing here'),
        ),
      );

      await tester.fling(find.byType(Scrollable), const Offset(0, 320), 1000);
      await tester.pumpAndSettle();
      expect(refreshed, isTrue);
    });

    testWidgets('renders the title, subtitle and action', (tester) async {
      await pump(
        tester,
        EmptyState(
          icon: Icons.inbox,
          title: 'No applications yet',
          subtitle: 'Apply and follow it here.',
          action: FilledButton(onPressed: () {}, child: const Text('Apply')),
        ),
      );
      expect(find.text('No applications yet'), findsOneWidget);
      expect(find.text('Apply and follow it here.'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });
  });

  group('ErrorRetry', () {
    testWidgets('shows the reason and retries', (tester) async {
      var retried = false;
      await pump(
        tester,
        ErrorRetry(
          message: 'Cannot reach the server.',
          onRetry: () => retried = true,
        ),
      );

      expect(find.text('Cannot reach the server.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('is scrollable too', (tester) async {
      await pump(tester, ErrorRetry(message: 'nope', onRetry: () {}));
      expect(find.byType(Scrollable), findsOneWidget);
    });
  });

  group('insets', () {
    testWidgets('a tab clears the footer nav, a pushed page does not', (
      tester,
    ) async {
      late EdgeInsets tab;
      late EdgeInsets page;
      await pump(
        tester,
        Builder(
          builder: (context) {
            tab = tabInsets(context);
            page = pageInsets(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(tab.left, page.left, reason: 'one page gutter for both');
      expect(
        tab.bottom,
        greaterThan(page.bottom),
        reason: 'only the tab has a 62px nav bar painted over it',
      );
    });
  });

  // ── The frame every pushed screen wears ─────────────────────────────────
  //
  // Settings, Profile, Refer & Earn, Alerts, Documents needed and Project
  // progress all sit on this. They used to get a stripped header — back arrow
  // and logo, no bell, no menu — so half the app had a sidebar and half did
  // not, and two of them (Documents needed, Project progress) had a bare
  // Material AppBar with no logo at all. One header, everywhere.
  group('PageScaffold header', () {
    testWidgets('carries the same bell and menu the tabs do', (tester) async {
      await tester.pumpWidget(
        harness(
          const PageScaffold(title: 'Settings', child: SizedBox.shrink()),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('drops ONLY the bell where it would point at itself', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const PageScaffold(
            title: 'Alerts',
            showAlerts: false,
            child: SizedBox.shrink(),
          ),
        ),
      );

      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      expect(
        find.byIcon(Icons.menu),
        findsOneWidget,
        reason: 'the menu is on every screen without exception',
      );
    });

    // The name used to be a caption inside the bar, hung under the wordmark.
    // It is the page's heading now, so it must sit BELOW the header rather than
    // within it — that placement is the whole of the fix.
    testWidgets('names the screen under the bar, not inside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const PageScaffold(title: 'Settings', child: SizedBox.shrink()),
        ),
      );

      expect(find.byType(PageTitle), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppHeader), matching: find.text('Settings')),
        findsNothing,
        reason: 'the screen name is back in the app bar',
      );
      expect(
        tester.getRect(find.text('Settings')).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(AppHeader)).bottom),
      );
    });

    testWidgets('the menu opens a sidebar of its own', (tester) async {
      await tester.pumpWidget(
        harness(const PageScaffold(title: 'Profile', child: SizedBox.shrink())),
      );

      expect(find.byType(AppDrawer), findsNothing);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(AppDrawer), findsOneWidget);
    });
  });

  testWidgets('SectionTitle upper-cases its heading', (tester) async {
    await pump(tester, const SectionTitle('Open requests'));
    expect(find.text('OPEN REQUESTS'), findsOneWidget);
  });
}
