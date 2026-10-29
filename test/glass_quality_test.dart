import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/materials.dart';

void main() {
  testWidgets('standard glass bypasses the backdrop filter layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MilkGlass(high: false, child: Text('玻璃面板'))),
      ),
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      false,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MilkGlass(high: true, child: Text('玻璃面板'))),
      ),
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      true,
    );
  });
}
