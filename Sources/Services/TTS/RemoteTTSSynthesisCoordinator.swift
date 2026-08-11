import Foundation

/// Serializes remote TTS work so a prefetch window describes buffered depth,
/// not the number of simultaneous network/JavaScript synthesis operations.
internal actor RemoteTTSSynthesisCoordinator {
    internal enum Priority: Int, Sendable {
        case current = 0
        case prefetch = 1
        case nextChapter = 2
    }

    internal static let shared = RemoteTTSSynthesisCoordinator()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Data, Error>
    }

    private struct Job {
        let key: String
        let engine: String
        let textLength: Int
        var priority: Priority
        let sequence: UInt64
        let operation: @Sendable () async throws -> Data
        var waiters: [Waiter]
    }

    private struct EnergyWindow {
        let startedAt: TimeInterval
        let applicationState: String
        var requests: Int = 0
        var successes: Int = 0
        var failures: Int = 0
        var cancellations: Int = 0
        var currentRequests: Int = 0
        var prefetchRequests: Int = 0
        var nextChapterRequests: Int = 0
        var deduplicatedWaiters: Int = 0
        var textCharacters: Int = 0
        var audioBytes: Int = 0
        var totalSynthesisMs: Double = 0
        var maxSynthesisMs: Double = 0
        var maxQueueDepth: Int = 0
        var engineRequests: [String: Int] = [:]
    }

    private static let energyLogInterval: TimeInterval = 60

    private var queue: [Job] = []
    private var activeJob: Job?
    private var activeTask: Task<Void, Never>?
    private var nextSequence: UInt64 = 0
    private var applicationState = "foreground"
    private var energyWindow: EnergyWindow?
    private var activeSynthesisStartedAt: TimeInterval?

    internal init() {}

    internal func synthesize(
        key: String,
        engine: String = "unknown",
        textLength: Int = 0,
        priority: Priority,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let waiterID = UUID()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                enqueue(
                    key: key,
                    engine: engine,
                    textLength: textLength,
                    priority: priority,
                    operation: operation,
                    waiter: Waiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancel(waiterID: waiterID)
            }
        }
    }

    internal func setApplicationState(_ state: String, engine: String, isPlaying: Bool) {
        guard state != applicationState else { return }
        emitEnergySummary(reason: "app_state_change")
        applicationState = state
        energyWindow = nil
        activeSynthesisStartedAt = nil
        AppLogger.shared.log("[TTSEnergy] AppState state=\(state) engine=\(engine) playing=\(isPlaying) thermal=\(Self.thermalStateName(ProcessInfo.processInfo.thermalState))")
    }

    internal func recordThermalStateChange(engine: String, isPlaying: Bool) {
        let thermal = ProcessInfo.processInfo.thermalState
        emitEnergySummary(reason: "thermal_change")
        energyWindow = nil
        activeSynthesisStartedAt = nil
        AppLogger.shared.log("[TTSEnergy] ThermalChange state=\(applicationState) engine=\(engine) playing=\(isPlaying) thermal=\(Self.thermalStateName(thermal))")
    }

    internal func cancelAll() {
        emitEnergySummary(reason: "cancel_all")
        energyWindow = nil
        activeSynthesisStartedAt = nil
        let cancellation = CancellationError()
        for job in queue {
            for waiter in job.waiters {
                waiter.continuation.resume(throwing: cancellation)
            }
        }
        queue.removeAll()

        if var activeJob {
            for waiter in activeJob.waiters {
                waiter.continuation.resume(throwing: cancellation)
            }
            activeJob.waiters.removeAll()
            self.activeJob = activeJob
        }
        activeTask?.cancel()
    }

    private func enqueue(
        key: String,
        engine: String,
        textLength: Int,
        priority: Priority,
        operation: @escaping @Sendable () async throws -> Data,
        waiter: Waiter
    ) {
        if var activeJob, activeJob.key == key, !activeJob.waiters.isEmpty {
            activeJob.waiters.append(waiter)
            self.activeJob = activeJob
            recordDeduplicatedWaiter()
            return
        }

        if let index = queue.firstIndex(where: { $0.key == key }) {
            queue[index].waiters.append(waiter)
            if priority.rawValue < queue[index].priority.rawValue {
                queue[index].priority = priority
            }
            sortQueue()
            recordDeduplicatedWaiter()
            return
        }

        nextSequence &+= 1
        queue.append(
            Job(
                key: key,
                engine: engine,
                textLength: textLength,
                priority: priority,
                sequence: nextSequence,
                operation: operation,
                waiters: [waiter]
            )
        )
        updateMaximumQueueDepth()
        sortQueue()
        startNextIfNeeded()
    }

    private func sortQueue() {
        queue.sort {
            if $0.priority.rawValue == $1.priority.rawValue {
                return $0.sequence < $1.sequence
            }
            return $0.priority.rawValue < $1.priority.rawValue
        }
    }

    private func startNextIfNeeded() {
        guard activeJob == nil, !queue.isEmpty else { return }

        let job = queue.removeFirst()
        activeJob = job
        let operation = job.operation
        let key = job.key
        recordSynthesisStart(for: job)

        activeTask = Task {
            let result: Result<Data, Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            self.complete(key: key, result: result)
        }
    }

    private func complete(key: String, result: Result<Data, Error>) {
        guard let completedJob = activeJob, completedJob.key == key else { return }

        recordSynthesisCompletion(result: result)
        activeJob = nil
        activeTask = nil
        for waiter in completedJob.waiters {
            waiter.continuation.resume(with: result)
        }
        startNextIfNeeded()
    }

    private func cancel(waiterID: UUID) {
        for index in queue.indices {
            if let waiterIndex = queue[index].waiters.firstIndex(where: { $0.id == waiterID }) {
                let waiter = queue[index].waiters.remove(at: waiterIndex)
                waiter.continuation.resume(throwing: CancellationError())
                if queue[index].waiters.isEmpty {
                    queue.remove(at: index)
                }
                return
            }
        }

        guard var activeJob,
              let waiterIndex = activeJob.waiters.firstIndex(where: { $0.id == waiterID }) else { return }

        let waiter = activeJob.waiters.remove(at: waiterIndex)
        waiter.continuation.resume(throwing: CancellationError())
        self.activeJob = activeJob

        if activeJob.waiters.isEmpty {
            activeTask?.cancel()
        }
    }

    private func ensureEnergyWindow(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard AppLogger.shared.isLoggingEnabled else {
            energyWindow = nil
            activeSynthesisStartedAt = nil
            return
        }
        if energyWindow == nil {
            energyWindow = EnergyWindow(startedAt: now, applicationState: applicationState)
        }
    }

    private func recordSynthesisStart(for job: Job) {
        let now = ProcessInfo.processInfo.systemUptime
        ensureEnergyWindow(now: now)
        guard var window = energyWindow else { return }

        window.requests += 1
        window.textCharacters += max(0, job.textLength)
        window.engineRequests[job.engine, default: 0] += 1
        switch job.priority {
        case .current:
            window.currentRequests += 1
        case .prefetch:
            window.prefetchRequests += 1
        case .nextChapter:
            window.nextChapterRequests += 1
        }
        energyWindow = window
        activeSynthesisStartedAt = now
    }

    private func recordSynthesisCompletion(result: Result<Data, Error>) {
        let now = ProcessInfo.processInfo.systemUptime
        guard var window = energyWindow,
              let startedAt = activeSynthesisStartedAt else { return }

        let synthesisMs = max(0, (now - startedAt) * 1_000)
        window.totalSynthesisMs += synthesisMs
        window.maxSynthesisMs = max(window.maxSynthesisMs, synthesisMs)
        switch result {
        case .success(let data):
            window.successes += 1
            window.audioBytes += data.count
        case .failure(let error):
            if error is CancellationError {
                window.cancellations += 1
            } else {
                window.failures += 1
            }
        }
        energyWindow = window
        activeSynthesisStartedAt = nil

        if now - window.startedAt >= Self.energyLogInterval {
            emitEnergySummary(reason: "interval", now: now)
        }
    }

    private func recordDeduplicatedWaiter() {
        ensureEnergyWindow()
        guard var window = energyWindow else { return }
        window.deduplicatedWaiters += 1
        energyWindow = window
    }

    private func updateMaximumQueueDepth() {
        ensureEnergyWindow()
        // Optional-chaining assignment that also reads energyWindow on its RHS
        // can hold an overlapping _modify access and trap at runtime.
        guard var window = energyWindow else { return }
        window.maxQueueDepth = max(window.maxQueueDepth, queue.count)
        energyWindow = window
    }

    private func emitEnergySummary(
        reason: String,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard let window = energyWindow, window.requests > 0 else {
            energyWindow = nil
            activeSynthesisStartedAt = nil
            return
        }

        let elapsedSeconds = max(1, now - window.startedAt)
        let requestsPerMinute = Double(window.requests) * 60 / elapsedSeconds
        let bytesPerMinute = Double(window.audioBytes) * 60 / elapsedSeconds
        let busyPercent = min(100, window.totalSynthesisMs / (elapsedSeconds * 10))
        let averageSynthesisMs = window.totalSynthesisMs / Double(window.requests)
        let engines = window.engineRequests.keys.sorted().map {
            "\($0):\(window.engineRequests[$0] ?? 0)"
        }.joined(separator: ",")
        let thermal = ProcessInfo.processInfo.thermalState
        let prediction: String
        if elapsedSeconds < 20 && window.requests < 3 {
            prediction = "insufficient_sample"
        } else {
            prediction = Self.energyPrediction(
                applicationState: window.applicationState,
                requestsPerMinute: requestsPerMinute,
                busyPercent: busyPercent,
                thermalState: thermal
            )
        }

        let logLine = String(
            format: "[TTSEnergy] Summary reason=%@ state=%@ engines=%@ elapsedSec=%.1f requests=%d rpm=%.1f current=%d prefetch=%d next=%d success=%d failure=%d cancelled=%d dedup=%d textChars=%d audioKB=%d audioKBPerMin=%.1f synthesisMs=%.1f avgMs=%.1f maxMs=%.1f busyPct=%.1f maxQueue=%d thermal=%@ prediction=%@",
            reason,
            window.applicationState,
            engines,
            elapsedSeconds,
            window.requests,
            requestsPerMinute,
            window.currentRequests,
            window.prefetchRequests,
            window.nextChapterRequests,
            window.successes,
            window.failures,
            window.cancellations,
            window.deduplicatedWaiters,
            window.textCharacters,
            window.audioBytes / 1_024,
            bytesPerMinute / 1_024,
            window.totalSynthesisMs,
            averageSynthesisMs,
            window.maxSynthesisMs,
            busyPercent,
            window.maxQueueDepth,
            Self.thermalStateName(thermal),
            prediction
        )
        AppLogger.shared.log(logLine)
        energyWindow = EnergyWindow(startedAt: now, applicationState: applicationState)
    }

    internal static func energyPrediction(
        applicationState: String,
        requestsPerMinute: Double,
        busyPercent: Double,
        thermalState: ProcessInfo.ThermalState
    ) -> String {
        if thermalState == .serious || thermalState == .critical {
            return "thermal_pressure_confirmed"
        }
        if applicationState == "background" && (requestsPerMinute >= 15 || busyPercent >= 50) {
            return "background_remote_load_likely"
        }
        if requestsPerMinute >= 18 || busyPercent >= 60 {
            return "sustained_remote_load_likely"
        }
        if requestsPerMinute >= 10 || busyPercent >= 30 {
            return "remote_load_elevated"
        }
        return "remote_load_low"
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
