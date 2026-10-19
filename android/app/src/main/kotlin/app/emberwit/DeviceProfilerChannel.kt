package app.emberwit

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Device facts the Dart device profiler needs and no plugin provides:
 * live memory (ActivityManager.MemoryInfo), thermal status (PowerManager),
 * storage (StatFs), CPU features and performance cores, Vulkan support, and
 * unpacking the bundled benchmark model from the APK.
 *
 * Work runs on a background thread; results are posted to the main thread.
 * Error codes are stable strings the Dart side maps to failures.
 */
class DeviceProfilerChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSnapshot" -> runInBackground(result) { snapshot() }
            "prepareAsset" -> {
                val asset = call.argument<String>("asset")
                val target = call.argument<String>("target")
                if (asset == null || target == null) {
                    result.error("bad_arguments", "asset and target are required", null)
                } else {
                    runInBackground(result) { prepareAsset(asset, target) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun runInBackground(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("native_error", e.javaClass.simpleName, null) }
            }
        }
    }

    private fun snapshot(): Map<String, Any?> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memory)
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val stat = StatFs(context.filesDir.path)
        val cores = Runtime.getRuntime().availableProcessors()
        return mapOf(
            "totalRamBytes" to memory.totalMem,
            "availableRamBytes" to memory.availMem,
            "lowMemory" to memory.lowMemory,
            "freeStorageBytes" to stat.availableBytes,
            "totalStorageBytes" to stat.totalBytes,
            "thermalState" to thermalState(power),
            "lowPowerMode" to power.isPowerSaveMode,
            "cpuCores" to cores,
            "performanceCores" to performanceCores(cores),
            "cpuFlags" to cpuFlags(),
            "gpuBackends" to gpuBackends(),
        )
    }

    private fun thermalState(power: PowerManager): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "unknown"
        return when (power.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "nominal"
            PowerManager.THERMAL_STATUS_LIGHT,
            PowerManager.THERMAL_STATUS_MODERATE -> "fair"
            PowerManager.THERMAL_STATUS_SEVERE -> "serious"
            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
            else -> "unknown"
        }
    }

    /**
     * Cores whose maximum frequency is at least 80% of the fastest core's.
     * On a 1+3+4 big.LITTLE phone this counts the prime and big cores.
     */
    private fun performanceCores(cores: Int): Int {
        val frequencies = (0 until cores).mapNotNull { i ->
            try {
                File("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq")
                    .readText().trim().toLong()
            } catch (e: Exception) {
                null
            }
        }
        if (frequencies.isEmpty()) return cores
        val fastest = frequencies.max()
        return frequencies.count { it >= fastest * 0.8 }
    }

    /** Raw feature flags from /proc/cpuinfo ("Features" on ARM, "flags" on x86). */
    private fun cpuFlags(): List<String> {
        return try {
            File("/proc/cpuinfo").useLines { lines ->
                lines.firstOrNull {
                    it.startsWith("Features") || it.startsWith("flags")
                }?.substringAfter(':')?.trim()?.split(Regex("\\s+")) ?: emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun gpuBackends(): List<String> {
        val pm = context.packageManager
        // Vulkan 1.1 (0x401000) is the minimum llama.cpp's Vulkan backend needs.
        return if (pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, 0x401000)) {
            listOf("vulkan")
        } else {
            emptyList()
        }
    }

    /**
     * Streams a Flutter asset out of the APK into [target] so native code can
     * open it by path. Skips the copy when an identical-size file exists.
     * Returns the path, or null when the asset is not bundled.
     */
    private fun prepareAsset(asset: String, target: String): String? {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        val out = File(target)
        val stream = try {
            context.assets.open(key)
        } catch (e: java.io.IOException) {
            return null
        }
        stream.use { input ->
            val size = try {
                context.assets.openFd(key).use { it.length }
            } catch (e: java.io.IOException) {
                -1L // Compressed asset: size unknown without reading it.
            }
            if (size > 0 && out.exists() && out.length() == size) return out.path
            out.parentFile?.mkdirs()
            val partial = File(out.path + ".part")
            partial.outputStream().use { input.copyTo(it, 1 shl 20) }
            if (!partial.renameTo(out)) throw java.io.IOException("rename failed")
        }
        return out.path
    }

    companion object {
        const val CHANNEL = "app.emberwit/device_profiler"
    }
}
