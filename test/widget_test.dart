import 'package:flutter_test/flutter_test.dart';

import 'package:autism_detection_mobile_replica/app/app.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(
      const AutismDetectionReplicaApp(),
    );

    expect(
      find.text('Mobile Replica - Step 1'),
      findsOneWidget,
    );

    expect(
      find.text('Create test session'),
      findsOneWidget,
    );
  });
}