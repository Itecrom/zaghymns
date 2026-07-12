import 'package:flutter_test/flutter_test.dart';

import 'package:zaghymn/main.dart';

void main() {
  testWidgets('shows app name on launch', (WidgetTester tester) async {
    await tester.pumpWidget(const ZombaHymnsApp());

    expect(find.text(brandTitle), findsOneWidget);
    expect(find.text(appTagline), findsOneWidget);
  });
}
