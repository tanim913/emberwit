package app.emberwit

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity because the biometric prompt (local_auth) is a
 * fragment.
 */
class MainActivity : FlutterFragmentActivity() {
    private var deviceProfiler: DeviceProfilerChannel? = null
    private var voiceInput: VoiceInputChannel? = null
    private var deviceActions: DeviceActionsChannel? = null
    private var window: MethodChannel? = null
    private var launch: MethodChannel? = null
    private var memory: MethodChannel? = null

    /** Action the app was opened for ("voice" from the widget), until Dart takes it. */
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) pendingAction = actionOf(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = actionOf(intent) ?: return
        val channel = launch
        if (channel == null) {
            pendingAction = action
        } else {
            channel.invokeMethod("action", action)
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        memory?.invokeMethod("trimMemory", level)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        // The whole system is low on memory: as serious as TRIM_MEMORY_COMPLETE.
        memory?.invokeMethod("trimMemory", TRIM_MEMORY_COMPLETE)
    }

    private fun actionOf(intent: Intent?): String? =
        if (intent?.action == ACTION_VOICE) "voice" else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        deviceProfiler = DeviceProfilerChannel(applicationContext, messenger)
        voiceInput = VoiceInputChannel(this, messenger)
        deviceActions = DeviceActionsChannel(this, messenger)
        // FLAG_SECURE while the app lock screen shows: no screenshots, screen
        // recording or recent apps thumbnail of the lock state.
        // Tells Dart what the app was opened for (the voice widget).
        launch = MethodChannel(messenger, "app.emberwit/launch").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takeAction") {
                    result.success(pendingAction)
                    pendingAction = null
                } else {
                    result.notImplemented()
                }
            }
        }
        // The real onTrimMemory level. Flutter reports "the app was hidden"
        // as memory pressure too, which would unload the model at every app
        // switch; Dart decides from the level instead.
        memory = MethodChannel(messenger, "app.emberwit/memory")
        window = MethodChannel(messenger, "app.emberwit/window").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.argument<Boolean>("secure") == true
                    if (secure) {
                        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        deviceProfiler?.dispose()
        deviceProfiler = null
        voiceInput?.dispose()
        voiceInput = null
        deviceActions?.dispose()
        deviceActions = null
        window?.setMethodCallHandler(null)
        window = null
        launch?.setMethodCallHandler(null)
        launch = null
        memory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Needed for permission results in FlutterFragmentActivity")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (voiceInput?.onPermissionResult(requestCode, grantResults) == true) return
        @Suppress("DEPRECATION")
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    companion object {
        /** Intent action of the home screen voice widget. */
        const val ACTION_VOICE = "app.emberwit.action.VOICE"
    }
}
