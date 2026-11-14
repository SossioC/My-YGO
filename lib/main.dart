import 'package:flutter/material.dart';

void main() => runApp(const MyYgoApp());

class AppColors {
  static const background = Color(0xFF0E0B14);
  static const surface = Color(0xFF1A1524);
  static const gold = Color(0xFFD4AF37);
  static const purple = Color(0xFF7B4FB8);
  static const textDim = Color(0xFF9A93A8);
}

class MyYgoApp extends StatelessWidget {
  const MyYgoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const scheme = ColorScheme.dark(
      primary: AppColors.gold,
      secondary: AppColors.purple,
      surface: AppColors.surface,
    );

    return MaterialApp(
      title: 'My YGO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.gold,
          centerTitle: true,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.purple.withAlpha(90),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    PlaceholderPage(
      icon: Icons.document_scanner_outlined,
      title: 'Scansione',
      subtitle: 'Qui scansionerai le carte in continuo.',
    ),
    PlaceholderPage(
      icon: Icons.style_outlined,
      title: 'Collezione',
      subtitle: 'Qui vedrai tutte le tue carte.',
    ),
    PlaceholderPage(
      icon: Icons.layers_outlined,
      title: 'Deck',
      subtitle: 'Qui creerai i tuoi deck.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MY YGO',
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold),
        ),
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Scansione',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: 'Collezione',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers),
            label: 'Deck',
          ),
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const PlaceholderPage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: AppColors.gold),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: AppColors.textDim)),
        ],
      ),
    );
  }
}
