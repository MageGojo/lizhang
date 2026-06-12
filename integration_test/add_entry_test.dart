import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lizhang/main.dart';
import 'package:lizhang/services/ledger_controller.dart';
import 'package:lizhang/services/ledger_database.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adds a manual ledger entry without crashing', (tester) async {
    final dir = await Directory.systemTemp.createTemp('lizhang-ui-add-');
    final database = LedgerDatabase(
      databasePath: p.join(dir.path, 'ui.sqlite'),
    );
    final controller = LedgerController(database);

    addTearDown(() async {
      await database.close();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    await tester.pumpWidget(LizhangApp(controller: controller));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(5));

    await tester.enterText(fields.at(1), '12.34');
    await tester.enterText(fields.at(3), '咖啡店');
    await tester.enterText(fields.at(4), '拿铁');

    final saveButton = find.widgetWithText(FilledButton, '保存');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final entry = controller.snapshot?.entries.single;
    expect(entry?.amountCents, 1234);
    expect(entry?.category, '餐饮');
    expect(entry?.merchant, '咖啡店');
  });
}
