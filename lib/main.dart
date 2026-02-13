import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/theme_provider.dart';
import 'core/navigation/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MizdahApp()));
}

class MizdahApp extends ConsumerWidget {
  const MizdahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Mizdah',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MizdahTheme.lightTheme,
      darkTheme: MizdahTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
