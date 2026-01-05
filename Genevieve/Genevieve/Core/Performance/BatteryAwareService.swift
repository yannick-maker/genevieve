import Foundation
import IOKit.ps
import Combine

/// Service that monitors battery state and adjusts app behavior for power efficiency
@MainActor
final class BatteryAwareService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var batteryLevel: Double = 1.0
    @Published private(set) var isOnBattery: Bool = false
    @Published private(set) var isLowPowerMode: Bool = false
    @Published private(set) var currentPowerMode: PowerMode = .normal

    // MARK: - Types

    enum PowerMode: String, CaseIterable {
        case performance   // Full features, no restrictions
        case normal        // Standard operation
        case balanced      // Reduced frequency
        case lowPower      // Minimal activity

        var observationInterval: TimeInterval {
            switch self {
            case .performance: return 0.5
            case .normal: return 1.0
            case .balanced: return 2.0
            case .lowPower: return 5.0
            }
        }

        var analysisInterval: TimeInterval {
            switch self {
            case .performance: return 15
            case .normal: return 30
            case .balanced: return 60
            case .lowPower: return 120
            }
        }

        var enableVisionAnalysis: Bool {
            switch self {
            case .performance, .normal: return true
            case .balanced, .lowPower: return false
            }
        }

        var maxConcurrentTasks: Int {
            switch self {
            case .performance: return 4
            case .normal: return 3
            case .balanced: return 2
            case .lowPower: return 1
            }
        }

        var displayName: String {
            switch self {
            case .performance: return "Performance"
            case .normal: return "Normal"
            case .balanced: return "Balanced"
            case .lowPower: return "Low Power"
            }
        }
    }

    struct BatteryState {
        var level: Double
        var isCharging: Bool
        var isOnAC: Bool
        var timeRemaining: TimeInterval?
    }

    // MARK: - Configuration

    private let lowBatteryThreshold: Double = 0.20
    private let criticalBatteryThreshold: Double = 0.10
    private let checkInterval: TimeInterval = 60

    // MARK: - State

    private var monitorTimer: Timer?
    private var userOverride: PowerMode?

    // MARK: - Callbacks

    var onPowerModeChange: ((PowerMode) -> Void)?

    // MARK: - Initialization

    init() {
        updateBatteryState()
        startMonitoring()
    }

    deinit {
        monitorTimer?.invalidate()
    }

    // MARK: - Public API

    /// Force a specific power mode (user override)
    func setPowerMode(_ mode: PowerMode?) {
        userOverride = mode
        updatePowerMode()
    }

    /// Get current recommended settings
    func getRecommendedSettings() -> OperationSettings {
        OperationSettings(
            observationInterval: currentPowerMode.observationInterval,
            analysisInterval: currentPowerMode.analysisInterval,
            enableVisionAnalysis: currentPowerMode.enableVisionAnalysis,
            maxConcurrentTasks: currentPowerMode.maxConcurrentTasks
        )
    }

    /// Check if an expensive operation should be deferred
    func shouldDeferExpensiveOperation() -> Bool {
        switch currentPowerMode {
        case .performance, .normal:
            return false
        case .balanced:
            return batteryLevel < 0.30
        case .lowPower:
            return true
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBatteryState()
            }
        }
    }

    private func updateBatteryState() {
        let state = getBatteryState()

        batteryLevel = state.level
        isOnBattery = !state.isOnAC
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        updatePowerMode()
    }

    private func updatePowerMode() {
        let oldMode = currentPowerMode

        // Check user override first
        if let override = userOverride {
            currentPowerMode = override
        } else {
            // Automatic mode selection
            currentPowerMode = calculateAutomaticMode()
        }

        if currentPowerMode != oldMode {
            onPowerModeChange?(currentPowerMode)
        }
    }

    private func calculateAutomaticMode() -> PowerMode {
        // On AC power with high battery
        if !isOnBattery && batteryLevel > 0.80 {
            return .performance
        }

        // On AC power
        if !isOnBattery {
            return .normal
        }

        // Low power mode enabled by system
        if isLowPowerMode {
            return .lowPower
        }

        // Critical battery
        if batteryLevel <= criticalBatteryThreshold {
            return .lowPower
        }

        // Low battery
        if batteryLevel <= lowBatteryThreshold {
            return .balanced
        }

        // On battery with reasonable charge
        return .normal
    }

    // MARK: - Battery State Reading

    private func getBatteryState() -> BatteryState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            // No battery (desktop Mac)
            return BatteryState(level: 1.0, isCharging: false, isOnAC: true, timeRemaining: nil)
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int ?? 100
            let maxCapacity = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            let powerSource = info[kIOPSPowerSourceStateKey] as? String ?? ""
            let timeRemaining = info[kIOPSTimeToEmptyKey] as? Int

            let level = Double(currentCapacity) / Double(maxCapacity)
            let isOnAC = powerSource == kIOPSACPowerValue as String

            return BatteryState(
                level: level,
                isCharging: isCharging,
                isOnAC: isOnAC,
                timeRemaining: timeRemaining.map { TimeInterval($0 * 60) }
            )
        }

        return BatteryState(level: 1.0, isCharging: false, isOnAC: true, timeRemaining: nil)
    }
}

// MARK: - Supporting Types

struct OperationSettings {
    var observationInterval: TimeInterval
    var analysisInterval: TimeInterval
    var enableVisionAnalysis: Bool
    var maxConcurrentTasks: Int
}

// MARK: - Performance Monitor

@MainActor
final class PerformanceMonitor: ObservableObject {
    // MARK: - Published State

    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var memoryFootprint: UInt64 = 0

    // MARK: - Thresholds

    private let cpuWarningThreshold: Double = 0.50
    private let memoryWarningThreshold: Double = 0.70
    private let updateInterval: TimeInterval = 5.0

    // MARK: - State

    private var monitorTimer: Timer?
    private var warningCallback: ((PerformanceWarning) -> Void)?

    // MARK: - Types

    enum PerformanceWarning {
        case highCPU(Double)
        case highMemory(Double)
        case memoryPressure
    }

    // MARK: - Initialization

    init() {
        updateMetrics()
        startMonitoring()
    }

    deinit {
        monitorTimer?.invalidate()
    }

    // MARK: - Public API

    func setWarningCallback(_ callback: @escaping (PerformanceWarning) -> Void) {
        warningCallback = callback
    }

    func getFormattedMemory() -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(memoryFootprint))
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
    }

    private func updateMetrics() {
        updateCPUUsage()
        updateMemoryUsage()
        checkThresholds()
    }

    private func updateCPUUsage() {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t()

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else {
            return
        }

        var totalCPU: Double = 0

        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)

            let infoResult = withUnsafeMutablePointer(to: &info) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), ptr, &count)
                }
            }

            if infoResult == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE)
            }
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))

        cpuUsage = totalCPU
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }

        if result == KERN_SUCCESS {
            memoryFootprint = info.resident_size

            // Calculate as percentage of physical memory
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            memoryUsage = Double(info.resident_size) / Double(physicalMemory)
        }
    }

    private func checkThresholds() {
        if cpuUsage > cpuWarningThreshold {
            warningCallback?(.highCPU(cpuUsage))
        }

        if memoryUsage > memoryWarningThreshold {
            warningCallback?(.highMemory(memoryUsage))
        }
    }
}

// MARK: - Memory Cache

/// Simple LRU cache for reducing memory pressure
final class MemoryCache<Key: Hashable, Value> {
    private var cache: [Key: Value] = [:]
    private var accessOrder: [Key] = []
    private let maxSize: Int
    private let lock = NSLock()

    init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        guard let value = cache[key] else { return nil }

        // Move to end (most recently used)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        return value
    }

    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }

        // Remove old entry if exists
        if cache[key] != nil {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        // Evict if at capacity
        while accessOrder.count >= maxSize {
            if let oldest = accessOrder.first {
                cache.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }
        }

        cache[key] = value
        accessOrder.append(key)
    }

    func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: key)
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        accessOrder.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}

// MARK: - Debouncer

/// Utility for debouncing frequent operations
final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue
    private let delay: TimeInterval

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    func debounce(_ action: @escaping () -> Void) {
        workItem?.cancel()

        let item = DispatchWorkItem(block: action)
        workItem = item

        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

// MARK: - Throttler

/// Utility for throttling frequent operations
final class Throttler {
    private var lastExecutionTime: Date?
    private let minimumInterval: TimeInterval
    private let queue: DispatchQueue
    private var pendingAction: (() -> Void)?
    private var timer: Timer?

    init(minimumInterval: TimeInterval, queue: DispatchQueue = .main) {
        self.minimumInterval = minimumInterval
        self.queue = queue
    }

    func throttle(_ action: @escaping () -> Void) {
        let now = Date()

        if let lastTime = lastExecutionTime {
            let elapsed = now.timeIntervalSince(lastTime)

            if elapsed >= minimumInterval {
                // Enough time has passed, execute immediately
                lastExecutionTime = now
                queue.async(execute: action)
            } else {
                // Schedule for later
                pendingAction = action
                scheduleDelayedExecution(after: minimumInterval - elapsed)
            }
        } else {
            // First execution
            lastExecutionTime = now
            queue.async(execute: action)
        }
    }

    private func scheduleDelayedExecution(after delay: TimeInterval) {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, let action = self.pendingAction else { return }
            self.lastExecutionTime = Date()
            self.pendingAction = nil
            self.queue.async(execute: action)
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        pendingAction = nil
    }
}
