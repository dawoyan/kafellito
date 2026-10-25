import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'store.dart';

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
      child: MaterialApp(
        title: 'Kafelito',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F78)),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
