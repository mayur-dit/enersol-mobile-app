import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:enersol_customer/shared/widgets/app_header.dart';
import 'package:enersol_customer/shared/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  setUpAll(useOfflineFonts);

  testWidgets('probe', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            appBar: AppHeader(
              title: 'DOCUMENTS',
              showBack: true,
              onBack: () {},
              onAlertsTap: () {},
              onMenuTap: () {},
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final w = tester.getSize(find.byType(MaterialApp)).width;
    stdout.writeln('SCREEN width=$w centre=${w / 2}');
    for (final e in {
      'logo': find.byType(AppLogo),
      'back': find.byIcon(Icons.arrow_back_ios_new),
      'bell': find.byIcon(Icons.notifications_none_rounded),
      'menu': find.byIcon(Icons.menu),
      'title': find.text('DOCUMENTS'),
      'header': find.byType(AppHeader),
    }.entries) {
      final r = tester.getRect(e.value);
      stdout.writeln(
        '${e.key}: l=${r.left.toStringAsFixed(2)} r=${r.right.toStringAsFixed(2)} '
        't=${r.top.toStringAsFixed(2)} b=${r.bottom.toStringAsFixed(2)} '
        'cx=${r.center.dx.toStringAsFixed(2)} cy=${r.center.dy.toStringAsFixed(2)}',
      );
    }

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3.0);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    File('PROBE_OUT/header.png')
        .writeAsBytesSync(bd!.buffer.asUint8List() as Uint8List);
    stdout.writeln('wrote png ${img.width}x${img.height}');
  });
}
