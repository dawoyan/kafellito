import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'store.dart';
import 'i18n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore()..load();
  runApp(KafelitoApp(store: store));
}

class KafelitoApp extends StatelessWidget {
  final AppStore store;
  const KafelitoApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          title: tr('Kafelito'),
          locale: Locale(store.lang),
          supportedLocales: const [Locale('en'), Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F78)), useMaterial3: true),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
