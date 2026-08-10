import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/symbol.dart';
import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/tracking_screen.dart';
import 'services/market_api.dart';
import 'services/supabase_config.dart';
import 'theme/app_colors.dart';

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
      theme: _buildTheme(),
      home: const AuthGate(),
    );
  }
}

/// CLAUDE.md "UI/UX Tasarım Kuralları" → "Modern BIST/Borsa Analitik (Koyu &
/// Tech Tema)"nı uygulayan tek tema tanımı: koyu slate arka plan/kart/metin
/// paleti, tipografi (başlıklarda semibold + sıkı tracking, ikincil
/// metinlerde slate-400, sayısal veri için monospace) ve buton/alan
/// görünümü. Asıl "glassmorphism" kart efekti (blur + yarı saydam zemin)
/// `ThemeData.cardTheme` ile ifade edilemediğinden `GlassCard` widget'ında
/// ayrıca uygulanıyor (bkz. widgets/glass_card.dart); buradaki `cardTheme`
/// sadece henüz `GlassCard`'a taşınmamış yerler için düz bir koyu geri
/// düşüş (fallback). Ekranlar zaten `Theme.of(context).textTheme
/// .titleMedium` gibi tema üzerinden okuduğundan bu tanım tek başına çoğu
/// ekrana otomatik yansır.
ThemeData _buildTheme() {
  final monoTextStyle = GoogleFonts.robotoMono(
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.slate100,
  );
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.slate950,
    fontFamily: GoogleFonts.inter().fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.cyan500,
      brightness: Brightness.dark,
      primary: AppColors.cyan500,
      secondary: AppColors.emerald400,
      error: AppColors.rose500,
      surface: AppColors.slate900,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.slate950,
      foregroundColor: AppColors.slate100,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: AppColors.slate100,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    textTheme: TextTheme(
      titleLarge: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.slate100,
      ),
      titleMedium: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.slate100,
      ),
      bodyMedium: const TextStyle(color: AppColors.slate100),
      bodySmall: const TextStyle(color: AppColors.slate400),
      // Etiket/ticker metinleri (madde 3): büyük harfe çevirme
      // (`.toUpperCase()`) çağrı yerinde yapılmalı, CSS text-transform
      // karşılığı olmadığından burada uygulanamaz.
      labelSmall: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        color: AppColors.slate400,
      ),
      // Sayısal veri/fiyatlar (madde 3): monospace + sıkı tracking.
      labelLarge: monoTextStyle,
    ),
    cardTheme: CardThemeData(
      color: AppColors.glassFill,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: AppColors.glassBorder.top,
      ),
    ),
    dividerTheme: DividerThemeData(color: AppColors.slate800.withValues(alpha: 0.8)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.slate900.withValues(alpha: 0.6),
      labelStyle: const TextStyle(color: AppColors.slate400),
      hintStyle: const TextStyle(color: AppColors.slate400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.slate800.withValues(alpha: 0.8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.slate800.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.cyan500),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.slate900.withValues(alpha: 0.6),
      selectedColor: AppColors.cyan500.withValues(alpha: 0.2),
      labelStyle: const TextStyle(color: AppColors.slate100),
      side: BorderSide(color: AppColors.slate800.withValues(alpha: 0.8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.slate100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: AppColors.slate800.withValues(alpha: 0.8)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.cyan500,
        foregroundColor: AppColors.slate950,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.cyan500),
    ),
    iconTheme: const IconThemeData(color: AppColors.slate400),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.slate900.withValues(alpha: 0.9),
      indicatorColor: AppColors.cyan500.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.slate100
              : AppColors.slate400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.cyan500
              : AppColors.slate400,
        ),
      ),
    ),
  );
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
  final _api = MarketApi();
  int _index = 0;

  // Bildirim listesinden bir sembole tıklanınca Grafik sekmesine, Favoriler
  // listesinden takip ikonuna basılınca Takip sekmesine bu sembolle geçmek
  // için: sembol aynı olsa bile hedef ekranın yeniden tepki vermesi
  // gerektiğinden (didUpdateWidget karşılaştırması için) her istekte artan
  // bir sayaç da taşınıyor.
  MarketSymbol? _chartRequestSymbol;
  int _chartRequestId = 0;
  MarketSymbol? _trackRequestSymbol;
  int _trackRequestId = 0;

  // Favoriler; Grafik, Bildirimler ve Favoriler sekmeleri aynı listeyi
  // paylaşıyor (RootShell'de tutulup aşağı aktarılıyor) ki bir sekmede
  // yapılan favori değişikliği diğerlerinde de görünsün — IndexedStack tüm
  // sekmeleri en baştan canlı tuttuğundan, her ekranın kendi başına ayrı ayrı
  // yüklemesi aralarında senkron kalmazdı.
  List<String> _favorites = [];

  // IndexedStack tüm sekmeleri en baştan canlı tutuyor (favori senkronu bunu
  // gerektiriyor, bkz. yukarısı), ama bu açılışta ziyaret edilmemiş
  // sekmelerin bile initState'teki network çağrılarını hemen ateşlemesine
  // yol açıyordu. Bunun yerine bir sekme sadece ilk ziyaret edildiğinde
  // gerçek widget'ı ile değiştiriliyor; sonrasında IndexedStack'in normal
  // state-koruma davranışı devam ediyor.
  final Set<int> _visitedTabs = {0};

  void _goToTab(int i) {
    setState(() {
      _index = i;
      _visitedTabs.add(i);
    });
  }

  static const _titles = [
    'Grafik ve Aylık En Düşük Değerler',
    'Bildirimler',
    'Favoriler',
    'Takip',
  ];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final list = await _api.getFavorites();
      if (!mounted) return;
      setState(() => _favorites = list);
    } catch (e) {
      // Sekmeler favoriler olmadan da açılabilir, ama kullanıcı en azından
      // neden boş göründüğünü bilsin (bkz. _toggleFavorite'teki aynı desen).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Favoriler yüklenemedi: $e')),
      );
    }
  }

  Future<void> _toggleFavorite(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final isFavorite = _favorites.contains(normalized);
    try {
      if (isFavorite) {
        final result = await _api.removeFromFavorites(normalized);
        if (!mounted) return;
        if (result.removed) {
          setState(() =>
              _favorites = _favorites.where((s) => s != result.symbol).toList());
        }
      } else {
        final result = await _api.addToFavorites(normalized);
        if (!mounted) return;
        if (result.added && !_favorites.contains(result.symbol)) {
          setState(() => _favorites = [..._favorites, result.symbol]..sort());
        }
      }
    } catch (e) {
      // Önceden burada hata sessizce yutuluyordu; kullanıcıya hiçbir şey
      // olmamış gibi görünüyordu (ör. favorites tablosu Supabase'de henüz
      // oluşturulmamışsa). Artık en azından bir SnackBar ile görünür.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Favori işlemi başarısız: $e')),
      );
    }
  }

  void _openChartFor(MarketSymbol symbol) {
    setState(() {
      _chartRequestSymbol = symbol;
      _chartRequestId++;
      _index = 0;
      _visitedTabs.add(0);
    });
  }

  void _openTrackingFor(MarketSymbol symbol) {
    setState(() {
      _trackRequestSymbol = symbol;
      _trackRequestId++;
      _index = 3;
      _visitedTabs.add(3);
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
          if (_visitedTabs.contains(0))
            HomeScreen(
              requestedSymbol: _chartRequestSymbol,
              requestId: _chartRequestId,
              favorites: _favorites,
            )
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(1))
            NotificationsScreen(
              onOpenChart: _openChartFor,
              favorites: _favorites,
              onToggleFavorite: _toggleFavorite,
            )
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(2))
            FavoritesScreen(
              favorites: _favorites,
              onToggleFavorite: _toggleFavorite,
              onTrack: _openTrackingFor,
            )
          else
            const SizedBox.shrink(),
          if (_visitedTabs.contains(3))
            TrackingScreen(
              requestedSymbol: _trackRequestSymbol,
              requestId: _trackRequestId,
            )
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goToTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Grafik'),
          NavigationDestination(
              icon: Icon(Icons.notifications), label: 'Bildirimler'),
          NavigationDestination(icon: Icon(Icons.star), label: 'Favoriler'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Takip'),
        ],
      ),
    );
  }
}
