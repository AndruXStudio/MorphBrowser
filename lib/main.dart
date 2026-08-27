import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/browser_home.dart';
import 'services/settings_service.dart';
import 'widgets/pixel_splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MorphBrowserApp());
}

class MorphBrowserApp extends StatefulWidget {
  const MorphBrowserApp({super.key});

  @override
  State<MorphBrowserApp> createState() => _MorphBrowserAppState();
}

class _MorphBrowserAppState extends State<MorphBrowserApp> {
  final _settings = SettingsService();
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _settings,
      child: Consumer<SettingsService>(
        builder: (context, s, _) {
          return MaterialApp(
            title: 'Morph Browser',
            debugShowCheckedModeBanner: false,
            themeMode: s.themeMode,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6750A4),
                brightness: Brightness.light,
              ),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                },
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFD0BCFF),
                brightness: Brightness.dark,
              ),
              pageTransitionsTheme: const PageTransitionsTheme(
                builders: {
                  TargetPlatform.android: ZoomPageTransitionsBuilder(),
                  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                },
              ),
            ),
            home: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _showSplash
                  ? PixelSplash(
                      key: const ValueKey('splash'),
                      onDone: () => setState(() => _showSplash = false),
                    )
                  : const BrowserHome(key: ValueKey('home')),
            ),
          );
        },
      ),
    );
  }
}
