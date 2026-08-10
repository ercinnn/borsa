import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:borsa_takip/main.dart';
import 'package:borsa_takip/services/supabase_config.dart';

void main() {
  setUpAll(() async {
    // supabase_flutter oturumu shared_preferences'ta saklıyor; testte gerçek
    // platform kanalı olmadığından mock initial values ile taklit ediliyor
    // (yoksa Supabase.initialize MissingPluginException ile patlıyor).
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  });

  testWidgets('Ana ekran Grafik ve Bildirimler sekmeleriyle açılır',
      (WidgetTester tester) async {
    // BorsaTakipApp/AuthGate oturum durumuna göre LoginScreen ile RootShell
    // arasında geçiş yapıyor; testte gerçek bir Supabase oturumu kurmak
    // pratik olmadığından (auth state mock'lamak gerekir), doğrudan
    // RootShell'i pump ediyoruz — bu smoke test'in amacı zaten ana
    // sekmelerin render olduğunu doğrulamak, auth akışını değil.
    await tester.pumpWidget(const MaterialApp(home: RootShell()));

    expect(find.text('Grafik'), findsOneWidget);
    expect(find.text('Bildirimler'), findsOneWidget);
  });
}
