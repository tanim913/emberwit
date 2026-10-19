# R8 rules for Emberwit release builds.
# Flutter's own keep rules are added by the Flutter Gradle plugin. Rules for
# platform channel and FFI entry points are added here as those phases land.

# Strip verbose/debug/info logging from release bytecode.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
