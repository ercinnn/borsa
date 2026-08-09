import 'package:flutter_test/flutter_test.dart';

import 'package:borsa_takip/main.dart';

void main() {
  testWidgets('Ana ekran Grafik ve Bildirimler sekmeleriyle açılır',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BorsaTakipApp());

    expect(find.text('Grafik'), findsOneWidget);
    expect(find.text('Bildirimler'), findsOneWidget);
  });
}
