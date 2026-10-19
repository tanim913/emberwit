package app.emberwit

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Voice typing with the phone's own speech recognizer, offline only.
 *
 * On Android 12 and later the on-device recognizer is used, which never
 * sends audio anywhere; when a phone has none, voice typing is unavailable
 * (there is no fallback to the network recognizer). On Android 8 to 11 the
 * default recognizer is asked to stay offline (EXTRA_PREFER_OFFLINE, "only
 * use an offline speech recognition engine").
 *
 * Audio and text are never stored or logged here. Recognized text is sent
 * to Dart on the event channel only.
 *
 * Error codes are stable strings the Dart side maps to messages.
 */
class VoiceInputChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, RecognitionListener {

    private val methods = MethodChannel(messenger, METHODS)
    private val events = EventChannel(messenger, EVENTS)
    private var sink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var installer: SpeechRecognizer? = null
    private var pendingStart: Pair<List<String>, MethodChannel.Result>? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        release()
        installer?.destroy()
        installer = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())
            "start", "install" -> {
                val tags = call.argument<List<String>>("tags")
                if (tags.isNullOrEmpty()) {
                    result.error("bad_arguments", "tags are required", null)
                } else if (call.method == "start") {
                    start(tags, result)
                } else {
                    install(tags, result)
                }
            }
            "stop" -> {
                recognizer?.stopListening()
                result.success(null)
            }
            "cancel" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun isAvailable(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        } else {
            SpeechRecognizer.isRecognitionAvailable(activity)
        }

    private fun start(tags: List<String>, result: MethodChannel.Result) {
        if (!isAvailable()) {
            result.error("unavailable", null, null)
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pendingStart?.second?.error("busy", null, null)
            pendingStart = tags to result
            ActivityCompat.requestPermissions(
                activity, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST,
            )
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            resolveAndListen(tags, result)
        } else {
            listen(newRecognizer(), tags.first())
            result.success(tags.first())
        }
    }

    /** Called by the activity; true when the request was this channel's. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val pending = pendingStart ?: return true
        pendingStart = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            start(pending.first, pending.second)
        } else {
            pending.second.error("permission", null, null)
        }
        return true
    }

    /**
     * Picks the first of [tags] (or another region of the same language)
     * that the on-device recognizer has installed and starts listening.
     * Reports "downloading", "not_installed" or "unsupported" otherwise.
     *
     * The same recognizer checks and listens: destroying a separate checker
     * unbinds the shared recognition service and drops the new session.
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun resolveAndListen(tags: List<String>, result: MethodChannel.Result) {
        val created = newRecognizer()
        created.checkRecognitionSupport(
            recognizeIntent(tags.first()),
            ContextCompat.getMainExecutor(activity),
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    if (recognizer !== created) {
                        result.error("busy", null, null)
                        return
                    }
                    val installed = pick(tags, support.installedOnDeviceLanguages)
                    val problem = when {
                        installed != null -> null
                        pick(tags, support.pendingOnDeviceLanguages) != null -> "downloading"
                        pick(tags, support.supportedOnDeviceLanguages) != null -> "not_installed"
                        else -> "unsupported"
                    }
                    if (problem != null) {
                        release()
                        result.error(problem, null, null)
                    } else {
                        listen(created, installed!!)
                        result.success(installed)
                    }
                }

                override fun onError(error: Int) {
                    if (recognizer !== created) {
                        result.error("busy", null, null)
                        return
                    }
                    // The recognizer cannot say; try the first tag and let
                    // recognition report what is missing.
                    listen(created, tags.first())
                    result.success(tags.first())
                }
            },
        )
    }

    private fun pick(tags: List<String>, available: List<String>): String? {
        tags.firstOrNull { tag -> available.any { it.equals(tag, ignoreCase = true) } }
            ?.let { tag -> return available.first { it.equals(tag, ignoreCase = true) } }
        val language = tags.first().substringBefore('-')
        return available.firstOrNull {
            it.substringBefore('-').equals(language, ignoreCase = true)
        }
    }

    /** Asks the system to download the offline pack (Android 13 and later). */
    private fun install(tags: List<String>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || !isAvailable()) {
            result.success(false)
            return
        }
        installer?.destroy()
        installer = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity).also {
            it.triggerModelDownload(recognizeIntent(tags.first()))
        }
        result.success(true)
    }

    /** Replaces any current recognizer with a new, offline one. */
    private fun newRecognizer(): SpeechRecognizer {
        release()
        val created = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
        } else {
            SpeechRecognizer.createSpeechRecognizer(activity)
        }
        created.setRecognitionListener(this)
        recognizer = created
        return created
    }

    private fun listen(target: SpeechRecognizer, tag: String) {
        target.startListening(recognizeIntent(tag))
    }

    private fun recognizeIntent(tag: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, tag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
        }

    private fun release() {
        recognizer?.setRecognitionListener(null)
        recognizer?.destroy()
        recognizer = null
    }

    private fun send(event: Map<String, Any?>) {
        sink?.success(event)
    }

    private fun text(results: Bundle?): String =
        results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull() ?: ""

    override fun onReadyForSpeech(params: Bundle?) = send(mapOf("type" to "ready"))

    override fun onRmsChanged(rmsdB: Float) =
        send(mapOf("type" to "level", "value" to rmsdB.toDouble()))

    override fun onPartialResults(partialResults: Bundle?) =
        send(mapOf("type" to "partial", "text" to text(partialResults)))

    override fun onResults(results: Bundle?) {
        send(mapOf("type" to "final", "text" to text(results)))
        release()
    }

    override fun onError(error: Int) {
        send(mapOf("type" to "error", "code" to errorCode(error)))
        release()
    }

    private fun errorCode(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
        SpeechRecognizer.ERROR_NO_MATCH,
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no_speech"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "unsupported"
        // Offline only: a network error means the language is not on the phone.
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
        SpeechRecognizer.ERROR_SERVER -> "not_installed"
        else -> "failed"
    }

    override fun onBeginningOfSpeech() {}

    override fun onBufferReceived(buffer: ByteArray?) {}

    override fun onEndOfSpeech() {}

    override fun onEvent(eventType: Int, params: Bundle?) {}

    companion object {
        const val METHODS = "app.emberwit/voice"
        const val EVENTS = "app.emberwit/voice/events"
        private const val PERMISSION_REQUEST = 7301
    }
}
