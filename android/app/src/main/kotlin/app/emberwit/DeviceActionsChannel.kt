package app.emberwit

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Phone actions asked for in chat: alarms and timers (handed to the clock
 * app), the flashlight (CameraManager torch mode, which needs no camera
 * permission) and opening launcher apps.
 *
 * Outcomes are stable strings: "done", "unavailable", "busy", "failed".
 * App names and packages are never logged.
 */
class DeviceActionsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cameras = activity.getSystemService(CameraManager::class.java)
    private var torchCamera: String? = null
    private var torchOn = false

    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            if (cameraId == torchCamera) torchOn = enabled
        }
    }

    init {
        channel.setMethodCallHandler(this)
        torchCamera = findTorchCamera()
        if (torchCamera != null) cameras?.registerTorchCallback(torchCallback, main)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        cameras?.unregisterTorchCallback(torchCallback)
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setAlarm" -> {
                val intent = Intent(AlarmClock.ACTION_SET_ALARM)
                val hour = call.argument<Int>("hour")
                if (hour != null) {
                    intent.putExtra(AlarmClock.EXTRA_HOUR, hour)
                        .putExtra(AlarmClock.EXTRA_MINUTES, call.argument<Int>("minute") ?: 0)
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                }
                result.success(startClock(intent))
            }
            "setTimer" -> {
                val seconds = call.argument<Int>("seconds") ?: 0
                val intent = Intent(AlarmClock.ACTION_SET_TIMER)
                    .putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                result.success(startClock(intent))
            }
            "setTorch" -> result.success(setTorch(call.argument<Boolean>("on")))
            "installedApps" -> {
                worker.execute {
                    val apps = try {
                        installedApps()
                    } catch (e: Exception) {
                        emptyList()
                    }
                    main.post { result.success(apps) }
                }
            }
            "openApp" -> {
                val pkg = call.argument<String>("package")
                result.success(if (pkg == null) "failed" else openApp(pkg))
            }
            else -> result.notImplemented()
        }
    }

    private fun startClock(intent: Intent): String = try {
        activity.startActivity(intent)
        "done"
    } catch (e: ActivityNotFoundException) {
        "unavailable"
    } catch (e: SecurityException) {
        "failed"
    }

    private fun findTorchCamera(): String? = try {
        cameras?.cameraIdList?.firstOrNull { id ->
            val info = cameras.getCameraCharacteristics(id)
            info.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                info.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        } ?: cameras?.cameraIdList?.firstOrNull { id ->
            cameras.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        }
    } catch (e: CameraAccessException) {
        null
    }

    /** Returns the outcome and the flashlight's state afterwards. */
    private fun setTorch(on: Boolean?): Map<String, Any> {
        val id = torchCamera ?: return mapOf("outcome" to "unavailable", "on" to false)
        val wanted = on ?: !torchOn
        return try {
            cameras!!.setTorchMode(id, wanted)
            torchOn = wanted
            mapOf("outcome" to "done", "on" to wanted)
        } catch (e: CameraAccessException) {
            val outcome = if (e.reason == CameraAccessException.CAMERA_IN_USE ||
                e.reason == CameraAccessException.MAX_CAMERAS_IN_USE
            ) "busy" else "failed"
            mapOf("outcome" to outcome, "on" to torchOn)
        } catch (e: IllegalArgumentException) {
            mapOf("outcome" to "unavailable", "on" to false)
        }
    }

    private fun installedApps(): List<Map<String, String>> {
        val pm = activity.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, PackageManager.MATCH_ALL)
            .filter { it.activityInfo.packageName != activity.packageName }
            .map {
                mapOf(
                    "label" to it.loadLabel(pm).toString(),
                    "package" to it.activityInfo.packageName,
                )
            }
            .distinctBy { it["package"] }
    }

    private fun openApp(pkg: String): String {
        val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
            ?: return "unavailable"
        return try {
            activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            "done"
        } catch (e: ActivityNotFoundException) {
            "unavailable"
        } catch (e: SecurityException) {
            "failed"
        }
    }

    companion object {
        const val CHANNEL = "app.emberwit/device_actions"
    }
}
