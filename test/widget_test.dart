import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:xtremflow/features/iptv/widgets/quality_selector_widget.dart';

void main() {
  testWidgets('QualitySelectorButton shows all presets when opened',
      (tester) async {
    StreamQuality? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QualitySelectorButton(
            current: StreamQuality.high,
            onSelected: (q) => selected = q,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(QualitySelectorButton));
    await tester.pumpAndSettle();

    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Haute'), findsOneWidget);
    expect(find.text('Moyenne'), findsOneWidget);
    expect(find.text('Basse'), findsOneWidget);

    await tester.tap(find.text('Basse'));
    await tester.pumpAndSettle();
    expect(selected, StreamQuality.low);
  });
}
