import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/materials.dart';
import 'package:manxia/ui/room_design.dart';

void main() {
  testWidgets('shared route chrome follows global quality and high contrast', (
    tester,
  ) async {
    for (final (high, contrast) in [
      (false, false),
      (true, false),
      (true, true),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: GlassPerformanceScope(
            high: high,
            child: MediaQuery(
              data: MediaQueryData(highContrast: contrast),
              child: const Scaffold(appBar: RoomGlassBar(title: '阅读统计')),
            ),
          ),
        ),
      );
      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        high && !contrast,
      );
    }
  });
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
