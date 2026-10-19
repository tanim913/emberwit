import 'package:emberwit/app/debug/engine_debug_page.dart';
import 'package:emberwit/app/shell/not_found_page.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:emberwit/core/preferences/general_preferences.dart';
import 'package:emberwit/core/providers/core_providers.dart';
import 'package:emberwit/features/chat/presentation/chat_page.dart';
import 'package:emberwit/features/chat/presentation/conversations_page.dart';
import 'package:emberwit/features/device_profiler/presentation/device_check_page.dart';
import 'package:emberwit/features/model_manager/presentation/models_page.dart';
import 'package:emberwit/features/onboarding/presentation/onboarding_page.dart';
import 'package:emberwit/features/settings/presentation/model_licenses_page.dart';
import 'package:emberwit/features/settings/presentation/settings_page.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// The app's single [GoRouter].
///
/// Kept alive for the app lifetime so navigation state survives rebuilds of
/// the widget tree. Until onboarding is done every location redirects to
/// onboarding. [initialLocation] exists for tests.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref, {String initialLocation = AppRoutes.home}) {
  final debugTools = ref.watch(flavorConfigProvider).enableDebugTools;
  final onboarded = ValueNotifier(ref.read(onboardingCompletedProvider));
  ref
    ..listen(onboardingCompletedProvider, (_, done) => onboarded.value = done)
    ..onDispose(onboarded.dispose);
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (!onboarded.value) return atOnboarding ? null : AppRoutes.onboarding;
      return atOnboarding ? AppRoutes.chats : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        redirect: (context, state) => AppRoutes.chats,
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.chats,
        name: 'chats',
        builder: (context, state) => const ConversationsPage(),
        routes: [
          GoRoute(
            path: ':id',
            name: 'chat',
            builder: (context, state) => ChatPage(
              conversationId: state.pathParameters['id']!,
              startVoice: state.uri.queryParameters['voice'] == '1',
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.models,
        name: 'models',
        builder: (context, state) => const ModelsPage(),
      ),
      GoRoute(
        path: AppRoutes.deviceCheck,
        name: 'device-check',
        builder: (context, state) => const DeviceCheckPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'model-licenses',
            name: 'model-licenses',
            builder: (context, state) => const ModelLicensesPage(),
          ),
        ],
      ),
      if (debugTools)
        GoRoute(
          path: AppRoutes.engineDebug,
          name: 'engine-debug',
          builder: (context, state) => const EngineDebugPage(),
        ),
    ],
    errorBuilder: (context, state) => const NotFoundPage(),
  );
  ref.onDispose(router.dispose);
  return router;
}
