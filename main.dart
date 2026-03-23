import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:facefootball/core/utils/log.dart';
import 'package:facefootball/firebase_options.dart';
import 'package:facefootball/presentation/common/common.dart';
import 'package:facefootball/presentation/navigation/navigation_routes.dart';
import 'package:facefootball/presentation/notifications/fcm_helper.dart';

import 'core/di/app_modules.dart';

/// ------------------------------
/// MAIN
/// ------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // No bloquear el arranque si esto tarda o falla.
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]));

  runZonedGuarded(() {
    // Arrancamos UI de inmediato (evita “splash infinito”)
    runApp(const AppBootstrapper());
  }, (error, stack) {
    // En release, captura errores que de otra forma quedan silenciosos.
    logError('Uncaught zone error: $error\n$stack');
  });
}

/// ------------------------------
/// BOOTSTRAPPER (pantalla de carga / error / retry)
/// ------------------------------
class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Timeout global para evitar espera infinita.
    await _bootstrapInternal().timeout(const Duration(seconds: 18));
  }

  Future<void> _bootstrapInternal() async {
    // 1) Firebase (puede demorar en release / red lenta)
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));

    // 2) DI
    AppModules().setup();

    // 3) Locale/idioma (si demora, también cortamos)
    final locale = await LanguageManager.init().timeout(const Duration(seconds: 6));

    // Guardar locale en cache provider
    inject<CacheProvider>().language = locale;

    // 4) FCM NO debe bloquear el arranque. Lo hacemos en background.
    unawaited(_initFCMInBackground());
  }

  Future<void> _initFCMInBackground() async {
    try {
      await FCMHelper().requestPermission().timeout(const Duration(seconds: 6));
      await FCMHelper().init().timeout(const Duration(seconds: 10));

      // start() después de init (no bloquea UI)
      FCMHelper().start();

      // Token: si falla, no es crítico para abrir la app
      final token = await FCMHelper().getToken().timeout(const Duration(seconds: 6));
      logSuccess('FCM Token: $token');
    } catch (e, st) {
      // Importante: no romper la app por notificaciones
      logWarning('FCM init non-fatal error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _SplashLoadingScreen(),
          );
        }

        if (snap.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _BootstrapErrorScreen(
              error: snap.error,
              onRetry: () {
                setState(() {
                  _bootstrapFuture = _bootstrap();
                });
              },
            ),
          );
        }

        // OK: arrancar app real
        return const MyApp();
      },
    );
  }
}

class _SplashLoadingScreen extends StatelessWidget {
  const _SplashLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No se pudo iniciar Facefootball.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------------------------
/// APP REAL
/// ------------------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

  static void setLocale(BuildContext context, Locale newLocale) {
    inject<CacheProvider>().language = newLocale;
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Nota: FCM ya fue inicializado en background. Aquí NO repetimos init().
    // Si tu app necesita "start()" por seguridad, lo dejamos, no bloquea.
    unawaited(_postStartInit());
  }

  Future<void> _postStartInit() async {
    try {
      FCMHelper().start();

      // Token y locale sin bloquear UI
      final token = await FCMHelper().getToken().timeout(const Duration(seconds: 6));
      logSuccess('FCM Token (post): $token');

      final locale = await LanguageManager.init().timeout(const Duration(seconds: 6));
      if (mounted) {
        MyApp.setLocale(context, locale);
      }
    } catch (e, st) {
      logWarning('Post init non-fatal error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cacheProvider = inject<CacheProvider>();

    return ScreenUtilInit(
      designSize: const Size(360, 790),
      minTextAdapt: true,
      builder: (context, child) {
        return AnimatedBuilder(
          animation: cacheProvider,
          builder: (context, _) {
            if (context.mounted) {
              LocalizationManager.update(context: context);
            }

            return MaterialApp.router(
              title: 'Facefootball',
              theme: AppStyles.appTheme,
              themeMode: ThemeMode.light,
              routerConfig: router,
              locale: cacheProvider.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) {
                return GestureDetector(
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: child,
                );
              },
              onGenerateTitle: (context) {
                LocalizationManager.init(context: context);
                return localizations.app_title;
              },
              debugShowCheckedModeBanner: false,
            );
          },
        );
      },
    );
  }
}