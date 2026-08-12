import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/root_tabs.dart';
import 'models/symbol.dart';
import 'screens/backtest_screen.dart';
import 'screens/comparison_screen.dart';
import 'screens/dividend_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/fundamentals_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/technical_screen.dart';
import 'screens/tracking_screen.dart';
import 'services/market_api.dart';
import 'services/supabase_config.dart';
import 'theme/app_colors.dart';
import 'widgets/scrollable_bottom_nav.dart';

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

  // Sekmeler artık pozisyonel int yerine sabit bir anahtarla (bkz.
  // models/root_tabs.dart) izleniyor: Ayarlar'dan sekme aç/kapa yapılınca
  // görünür sekme listesi değişse de (dolayısıyla bir int index'in neye
  // karşılık geldiği kayabilir), bir anahtar her zaman aynı sekmeyi işaret
  // eder. `_tabOrder`, IndexedStack'in sabit çocuk sırası (Ayarlar dahil);
  // alt gezinme çubuğu bunun gizli olmayan bir alt kümesini gösterir.
  static const _tabOrder = [...toggleableRootTabs, settingsRootTab];
  String _selectedKey = toggleableRootTabs.first.key;

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

  // Ayarlar sekmesinde kapatılmış sekmelerin anahtarları (Supabase'de
  // tab_preferences tablosunda kullanıcı başına saklanır, bkz. MarketApi
  // .getHiddenTabs/setHiddenTabs). Boş = tüm sekmeler açık. Ayarlar
  // sekmesinin kendisi hiç bu kümeye giremez (SettingsScreen'e sadece
  // toggleableRootTabs veriliyor).
  Set<String> _hiddenTabs = {};

  // IndexedStack tüm sekmeleri en baştan canlı tutuyor (favori senkronu bunu
  // gerektiriyor, bkz. yukarısı), ama bu açılışta ziyaret edilmemiş
  // sekmelerin bile initState'teki network çağrılarını hemen ateşlemesine
  // yol açıyordu. Bunun yerine bir sekme sadece ilk ziyaret edildiğinde
  // gerçek widget'ı ile değiştiriliyor; sonrasında IndexedStack'in normal
  // state-koruma davranışı devam ediyor.
  final Set<String> _visitedTabs = {toggleableRootTabs.first.key};

  void _goToTab(String key) {
    setState(() {
      _selectedKey = key;
      _visitedTabs.add(key);
    });
  }

  /// Şu an açık sekme Ayarlar'dan kapatılırsa görünür ilk sekmeye geç
  /// (hiçbiri açık değilse Ayarlar'da kal — o her zaman görünür).
  void _leaveIfHidden() {
    if (!_hiddenTabs.contains(_selectedKey)) return;
    final firstVisible = toggleableRootTabs
        .map((t) => t.key)
        .firstWhere((k) => !_hiddenTabs.contains(k), orElse: () => settingsRootTab.key);
    _selectedKey = firstVisible;
    _visitedTabs.add(firstVisible);
  }

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadHiddenTabs();
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

  Future<void> _loadHiddenTabs() async {
    try {
      final hidden = await _api.getHiddenTabs();
      if (!mounted) return;
      setState(() {
        _hiddenTabs = hidden.toSet();
        _leaveIfHidden();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sekme ayarları yüklenemedi: $e')),
      );
    }
  }

  Future<void> _setTabHidden(String key, bool hidden) async {
    final next = Set<String>.from(_hiddenTabs);
    if (hidden) {
      next.add(key);
    } else {
      next.remove(key);
    }
    try {
      await _api.setHiddenTabs(next.toList());
      if (!mounted) return;
      setState(() {
        _hiddenTabs = next;
        _leaveIfHidden();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sekme ayarı kaydedilemedi: $e')),
      );
    }
  }

  /// Bir sekmeye bildirim/kısayol üzerinden doğrudan gidilirken o sekme
  /// Ayarlar'dan kapatılmış olabilir; kullanıcı açıkça o içeriği istediği
  /// için sekmeyi sessizce tekrar görünür yapıyoruz (bkz. SettingsScreen'in
  /// açıklama metni) — aksi halde alt gezinme çubuğunda ona karşılık gelen
  /// bir düğme olmadan sadece içerik açılırdı.
  void _unhideIfNeeded(String key) {
    if (_hiddenTabs.contains(key)) {
      _setTabHidden(key, false);
    }
  }

  void _openChartFor(MarketSymbol symbol) {
    setState(() {
      _chartRequestSymbol = symbol;
      _chartRequestId++;
      _selectedKey = 'chart';
      _visitedTabs.add('chart');
    });
    _unhideIfNeeded('chart');
  }

  void _openTrackingFor(MarketSymbol symbol) {
    setState(() {
      _trackRequestSymbol = symbol;
      _trackRequestId++;
      _selectedKey = 'tracking';
      _visitedTabs.add('tracking');
    });
    _unhideIfNeeded('tracking');
  }

  Widget _buildTabChild(String key) {
    if (!_visitedTabs.contains(key)) return const SizedBox.shrink();
    switch (key) {
      case 'chart':
        return HomeScreen(
          requestedSymbol: _chartRequestSymbol,
          requestId: _chartRequestId,
          favorites: _favorites,
          onToggleFavorite: _toggleFavorite,
        );
      case 'notifications':
        return NotificationsScreen(
          onOpenChart: _openChartFor,
          favorites: _favorites,
          onToggleFavorite: _toggleFavorite,
        );
      case 'favorites':
        return FavoritesScreen(
          favorites: _favorites,
          onToggleFavorite: _toggleFavorite,
          onTrack: _openTrackingFor,
        );
      case 'tracking':
        return TrackingScreen(
          requestedSymbol: _trackRequestSymbol,
          requestId: _trackRequestId,
        );
      case 'technical':
        return TechnicalScreen(favorites: _favorites);
      case 'comparison':
        return const ComparisonScreen();
      case 'portfolio':
        return const PortfolioScreen();
      case 'dividend':
        return const DividendScreen();
      case 'backtest':
        return const BacktestScreen();
      case 'fundamentals':
        return const FundamentalsScreen();
      case 'settings':
        return SettingsScreen(hiddenTabs: _hiddenTabs, onSetHidden: _setTabHidden);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _tabOrder.firstWhere((t) => t.key == _selectedKey).title;
    final navItems = [
      for (final tab in toggleableRootTabs)
        if (!_hiddenTabs.contains(tab.key))
          TabNavItem(key: tab.key, label: tab.navLabel, icon: tab.icon),
      TabNavItem(
        key: settingsRootTab.key,
        label: settingsRootTab.navLabel,
        icon: settingsRootTab.icon,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Borsa Takip · $title'),
        actions: [
          IconButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabOrder.indexWhere((t) => t.key == _selectedKey),
        children: [for (final tab in _tabOrder) _buildTabChild(tab.key)],
      ),
      bottomNavigationBar: ScrollableBottomNav(
        items: navItems,
        selectedKey: _selectedKey,
        onSelect: _goToTab,
      ),
    );
  }
}
