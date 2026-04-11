import Foundation
import IOKit.ps

@Observable
final class PowerMonitor {
    static let shared = PowerMonitor()

    private(set) var isOnACPower: Bool = true
    private var runLoopSource: CFRunLoopSource?

    private init() {
        updatePowerState()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func updatePowerState() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [Any],
              !sources.isEmpty
        else {
            isOnACPower = true // Default to AC if we can't determine
            return
        }

        // Check the overall power source type
        let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as? String
        isOnACPower = type == kIOPSACPowerValue as String
    }

    private func startMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.updatePowerState()
            }
        }, context)?.takeRetainedValue()

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
    }
}
