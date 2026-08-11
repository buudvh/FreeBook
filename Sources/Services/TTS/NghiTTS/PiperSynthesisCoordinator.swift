import Foundation

internal enum SynthesisPriority: Int, Comparable, Sendable {
    case low = 1      // Next-chapter paragraph 0 audio promotion
    case normal = 2   // Current-chapter sliding window prefetch (N+1, N+2...)
    case high = 3     // Current active playing paragraph (Immediate playback demand)

    internal static func < (lhs: SynthesisPriority, rhs: SynthesisPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

internal struct PiperSynthesisPayload: Sendable {
    internal let data: Data
    internal let pcmDuration: Double
    internal let queueWaitMs: Double
    internal let synthesisMs: Double

    internal init(
        data: Data,
        pcmDuration: Double,
        queueWaitMs: Double = 0.0,
        synthesisMs: Double = 0.0
    ) {
        self.data = data
        self.pcmDuration = pcmDuration
        self.queueWaitMs = queueWaitMs
        self.synthesisMs = synthesisMs
    }
}

internal actor PiperSynthesisCoordinator {
    internal static let shared = PiperSynthesisCoordinator()
    
    private struct PendingRequest {
        let id: UUID
        let priority: SynthesisPriority
        let sequenceNumber: UInt64
        let enqueuedAt: TimeInterval
        let work: @Sendable () async throws -> PiperSynthesisPayload
        var continuation: CheckedContinuation<PiperSynthesisPayload, Error>?
        var isCancelled: Bool = false
    }
    
    private var pendingQueue: [PendingRequest] = []
    private var activeRequest: PendingRequest? = nil
    private var isProcessing = false
    private var nextSequenceNumber: UInt64 = 0
    
    internal func enqueue(
        priority: SynthesisPriority,
        requestID: UUID,
        work: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let payload = try await enqueuePayload(priority: priority, requestID: requestID) {
            let data = try await work()
            return PiperSynthesisPayload(data: data, pcmDuration: 0.0)
        }
        return payload.data
    }

    internal func enqueuePayload(
        priority: SynthesisPriority,
        requestID: UUID,
        work: @escaping @Sendable () async throws -> PiperSynthesisPayload
    ) async throws -> PiperSynthesisPayload {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.nextSequenceNumber += 1
                let req = PendingRequest(
                    id: requestID,
                    priority: priority,
                    sequenceNumber: self.nextSequenceNumber,
                    enqueuedAt: ProcessInfo.processInfo.systemUptime,
                    work: work,
                    continuation: continuation,
                    isCancelled: Task.isCancelled
                )
                
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                self.pendingQueue.append(req)
                self.pendingQueue.sort {
                    if $0.priority != $1.priority {
                        return $0.priority > $1.priority
                    } else {
                        return $0.sequenceNumber < $1.sequenceNumber
                    }
                }
                self.processNextIfNeeded()
            }
        } onCancel: {
            Task {
                await self.cancelRequest(id: requestID)
            }
        }
    }
    
    internal func cancelRequest(id: UUID) {
        if let idx = pendingQueue.firstIndex(where: { $0.id == id }) {
            var req = pendingQueue.remove(at: idx)
            self.resumeContinuation(&req, with: .failure(CancellationError()))
            return
        }
        
        if activeRequest?.id == id {
            activeRequest?.isCancelled = true
        }
    }

    private func resumeContinuation(_ req: inout PendingRequest, with result: Result<PiperSynthesisPayload, Error>) {
        guard let continuation = req.continuation else { return }
        req.continuation = nil
        continuation.resume(with: result)
    }
    
    private func processNextIfNeeded() {
        guard !isProcessing, !pendingQueue.isEmpty else { return }
        isProcessing = true
        
        Task {
            while !pendingQueue.isEmpty {
                var req = pendingQueue.removeFirst()
                
                if req.isCancelled {
                    self.resumeContinuation(&req, with: .failure(CancellationError()))
                    continue
                }
                
                self.activeRequest = req
                
                do {
                    let synthesisStartedAt = ProcessInfo.processInfo.systemUptime
                    let result = try await req.work()
                    let synthesisFinishedAt = ProcessInfo.processInfo.systemUptime
                    let measuredResult = PiperSynthesisPayload(
                        data: result.data,
                        pcmDuration: result.pcmDuration,
                        queueWaitMs: max(0, (synthesisStartedAt - req.enqueuedAt) * 1_000),
                        synthesisMs: max(0, (synthesisFinishedAt - synthesisStartedAt) * 1_000)
                    )
                    if self.activeRequest?.id == req.id && self.activeRequest?.isCancelled == true {
                        if AppLogger.shared.isLoggingEnabled {
                            AppLogger.shared.log(String(
                                format: "[NghiEnergy] DiscardedActiveSynthesis synthesisMs=%.2f thermal=%@",
                                measuredResult.synthesisMs,
                                Self.thermalStateName(ProcessInfo.processInfo.thermalState)
                            ))
                        }
                        self.resumeContinuation(&req, with: .failure(CancellationError()))
                    } else {
                        self.resumeContinuation(&req, with: .success(measuredResult))
                    }
                } catch {
                    if self.activeRequest?.id == req.id && self.activeRequest?.isCancelled == true {
                        self.resumeContinuation(&req, with: .failure(CancellationError()))
                    } else {
                        self.resumeContinuation(&req, with: .failure(error))
                    }
                }
                
                self.activeRequest = nil
            }
            self.isProcessing = false
        }
    }
    
    internal func cancelAllPending() {
        for var req in pendingQueue {
            self.resumeContinuation(&req, with: .failure(CancellationError()))
        }
        pendingQueue.removeAll()
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
