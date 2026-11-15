import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/card_repository.dart';
import 'screens/collection_page.dart';
import 'screens/decks_page.dart';
import 'screens/scan_page.dart';
import 'services/backup_service.dart';
import 'theme.dart';
import 'widgets/dialogs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyYgoApp());
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

  @override
  void initState() {
    super.initState();
    // Scarica in background le immagini che mancano (dopo un import o un reinstall).
    unawaited(CardRepository.instance.cacheMissingImages());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<String> Function() job) async {
    try {
      _snack(await job());
    } catch (e) {
      _snack('Errore: $e');
    }
  }

  Future<void> _import() async {
    try {
      final data = await BackupService.pickBackup();
      if (data == null) return;
      final nCards = (data['cards'] as List).length;
      final nDecks = (data['decks'] is List) ? (data['decks'] as List).length : 0;
      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Importare il backup?',
        message:
            'Il file contiene $nCards carte e $nDecks deck.\n\nATTENZIONE: tutta la collezione e tutti i deck attuali verranno SOSTITUITI con quelli del file.',
        confirm: 'Sostituisci tutto',
      );
      if (!ok) return;
      final r = await BackupService.importData(data);
      unawaited(CardRepository.instance.cacheMissingImages());
      _snack('Importate ${r[0]} carte e ${r[1]} deck.');
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Importazione non riuscita: $e');
    }
  }

  void _onMenu(String value) {
    switch (value) {
      case 'json':
        _run(BackupService.exportJson);
        break;
      case 'csv':
        _run(BackupService.exportCsv);
        break;
      case 'import':
        _import();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MY YGO',
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Backup',
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'json', child: Text('Esporta backup (JSON)')),
              PopupMenuItem(value: 'csv', child: Text('Esporta collezione (CSV)')),
              PopupMenuItem(value: 'import', child: Text('Importa backup')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          ScanPage(active: _index == 0),
          const CollectionPage(),
          const DecksPage(),
        ],
      ),
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
