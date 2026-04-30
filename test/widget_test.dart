import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guitar_tuner/main.dart';

void main() {
  testWidgets('앱이 정상적으로 실행된다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: GuitarTunerApp()),
    );

    expect(find.text('Guitar Tuner'), findsOneWidget);
  });
}
