import Flutter
import Metal
import os
import UIKit

/// Device facts the Dart device profiler needs: memory (ProcessInfo and
/// os_proc_available_memory), thermal state, low power mode, storage, CPU
/// features and performance cores (sysctl), Metal support, and the path of
/// the bundled benchmark model.
final class DeviceProfilerChannel: NSObject {
  static let name = "app.emberwit/device_profiler"

  private let channel: FlutterMethodChannel
  private let registrar: FlutterPluginRegistrar

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSnapshot":
      DispatchQueue.global(qos: .userInitiated).async {
        let snapshot = Self.snapshot()
        DispatchQueue.main.async { result(snapshot) }
      }
    case "prepareAsset":
      guard let args = call.arguments as? [String: Any],
        let asset = args["asset"] as? String
      else {
        result(FlutterError(code: "bad_arguments", message: "asset is required", details: nil))
        return
      }
      // Assets are plain files inside the app bundle on iOS: no copy needed.
      let key = registrar.lookupKey(forAsset: asset)
      let path = Bundle.main.path(forResource: key, ofType: nil)
      result(path)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func snapshot() -> [String: Any] {
    let info = ProcessInfo.processInfo
    var free: Int64 = 0
    var total: Int64 = 0
    let home = URL(fileURLWithPath: NSHomeDirectory())
    if let values = try? home.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
    ]) {
      free = values.volumeAvailableCapacityForImportantUsage ?? 0
      total = Int64(values.volumeTotalCapacity ?? 0)
    }
    return [
      "totalRamBytes": Int64(info.physicalMemory),
      // What this app may still allocate before iOS terminates it. Honours
      // the increased memory limit entitlement.
      "availableRamBytes": Int64(os_proc_available_memory()),
      "lowMemory": false,
      "freeStorageBytes": free,
      "totalStorageBytes": total,
      "thermalState": thermalState(info.thermalState),
      "lowPowerMode": info.isLowPowerModeEnabled,
      "cpuCores": info.activeProcessorCount,
      "performanceCores": sysctlInt("hw.perflevel0.physicalcpu") ?? info.activeProcessorCount,
      "cpuFlags": cpuFlags(),
      "gpuBackends": MTLCreateSystemDefaultDevice() != nil ? ["metal"] : [],
    ]
  }

  private static func thermalState(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  private static func cpuFlags() -> [String] {
    let features = ["FEAT_DotProd", "FEAT_I8MM", "FEAT_FP16", "FEAT_BF16", "FEAT_SME"]
    return features.filter { sysctlInt("hw.optional.arm.\($0)") == 1 }
  }

  private static func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
  }
}

/// Storage helpers the model manager needs: excluding the models directory
/// from iCloud backup (models are large and re-downloadable, and chats must
/// never leave the device).
final class StorageChannel: NSObject {
  static let name = "app.emberwit/storage"

  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.name, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(FlutterError(code: "io", message: "exclude failed", details: nil))
      }
    }
  }
}
