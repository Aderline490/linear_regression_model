import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orphan_education_predictor/main.dart';

void main() {
  testWidgets('Prediction page renders all inputs, button and result area', (WidgetTester tester) async {
    await tester.pumpWidget(const MissionApp());

    expect(find.text('Education Access Predictor'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Predict'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(10));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(
      find.text('Fill in the fields above and press Predict to see a result here.'),
      findsOneWidget,
    );
  });
}
