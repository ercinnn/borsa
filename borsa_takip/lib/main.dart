import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/notifications_screen.dart';

void main() {
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
      home: const RootShell(),
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

  static const _titles = ['Grafik ve Aylık En Düşük Değerler', 'Bildirimler'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Borsa Takip · ${_titles[_index]}')),
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          NotificationsScreen(),
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
