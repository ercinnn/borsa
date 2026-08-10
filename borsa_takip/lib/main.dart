import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/symbol.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const BorsaTakipApp());
}

class BorsaTakipApp extends StatelessWidget {
  const BorsaTakipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Borsa Takip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Oturum durumuna göre giriş ekranı ile ana uygulama arasında geçiş yapar.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStateStream =
      Supabase.instance.client.auth.onAuthStateChange;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStateStream,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        Supabase.instance.client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
        return session == null ? const LoginScreen() : const RootShell();
      },
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  // Bildirim listesinden bir sembole tıklanınca Grafik sekmesine bu
  // sembolle geçmek için: sembol aynı olsa bile HomeScreen'in yeniden
  // tepki vermesi gerektiğinden (didUpdateWidget karşılaştırması için)
  // her istekte artan bir sayaç da taşınıyor.
  MarketSymbol? _chartRequestSymbol;
  int _chartRequestId = 0;

  static const _titles = ['Grafik ve Aylık En Düşük Değerler', 'Bildirimler'];

  void _openChartFor(MarketSymbol symbol) {
    setState(() {
      _chartRequestSymbol = symbol;
      _chartRequestId++;
      _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Borsa Takip · ${_titles[_index]}'),
        actions: [
          IconButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            requestedSymbol: _chartRequestSymbol,
            requestId: _chartRequestId,
          ),
          NotificationsScreen(onOpenChart: _openChartFor),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Grafik'),
          NavigationDestination(
              icon: Icon(Icons.notifications), label: 'Bildirimler'),
        ],
      ),
    );
  }
}
