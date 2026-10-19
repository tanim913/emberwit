/// Every route path of the app, in one place.
///
/// Lives in core so features can link to each other's screens without
/// importing each other. Features never hard code paths; they use these
/// constants or path builders.
abstract final class AppRoutes {
  /// Home: redirects to the conversation list.
  static const String home = '/';

  /// First run introduction.
  static const String onboarding = '/welcome';

  /// Settings.
  static const String settings = '/settings';

  /// Licenses of the language models.
  static const String modelLicenses = '/settings/model-licenses';

  /// Conversation list.
  static const String chats = '/chats';

  /// One conversation.
  static String chat(String id) => '/chats/$id';

  /// One conversation, listening for voice typing as soon as it opens.
  static String chatWithVoice(String id) => '/chats/$id?voice=1';

  /// Models: installed, downloading and available to download.
  static const String models = '/models';

  /// Device check: performance class, speed test and details.
  static const String deviceCheck = '/device';

  /// Engine debug screen. Registered only when debug tools are enabled.
  static const String engineDebug = '/debug/engine';
}
