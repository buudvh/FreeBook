import Foundation

internal enum SynthesisPriority: Int, Comparable, Sendable {
    case optionalReserve = 1      // N+2+ optional reserve audio
    case nextChapterMandatory = 2 // K+1 paragraph 0 mandatory audio
    case immediateSuccessor = 3   // N+1 stream immediate successor
    case demand = 4               // Current active missing audio demand

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

    private struct Waiter {
        let waiterID: UUID
        let requestID: UUID
        let continuation: CheckedContinuation<PiperSynthesisPayload, Error>
    }

    private struct PendingRequest {
        let synthesisKey: String?
        var priority: SynthesisPriority
        let sequenceNumber: UInt64
        let enqueuedAt: TimeInterval
        let work: @Sendable () async throws -> PiperSynthesisPayload
        var waiters: [Waiter]
    }

    private struct ActiveRequest {
        let id: UUID
        let synthesisKey: String?
        let enqueuedAt: TimeInterval
        let work: @Sendable () async throws -> PiperSynthesisPayload
        var waiters: [Waiter]
    }

    private var pendingQueue: [PendingRequest] = []
    private var activeRequest: ActiveRequest? = nil
    private var isProcessing = false
    private var nextSequenceNumber: UInt64 = 0

    internal func enqueue(
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String? = nil,
        work: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let payload = try await enqueuePayload(priority: priority, requestID: requestID, synthesisKey: synthesisKey) {
            let data = try await work()
            return PiperSynthesisPayload(data: data, pcmDuration: 0.0)
        }
        return payload.data
    }

    internal func enqueuePayload(
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String? = nil,
        work: @escaping @Sendable () async throws -> PiperSynthesisPayload
    ) async throws -> PiperSynthesisPayload {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(waiterID: waiterID, requestID: requestID, continuation: continuation)

                if let synthesisKey = synthesisKey {
                    if let idx = self.pendingQueue.firstIndex(where: { $0.synthesisKey == synthesisKey }) {
                        self.pendingQueue[idx].waiters.append(waiter)
                        if priority > self.pendingQueue[idx].priority {
                            self.pendingQueue[idx].priority = priority
                            self.sortPendingQueue()
                        }
                        return
                    }
                    if var active = self.activeRequest, active.synthesisKey == synthesisKey {
                        active.waiters.append(waiter)
                        self.activeRequest = active
                        return
                    }
                }

                self.nextSequenceNumber += 1
                let req = PendingRequest(
                    synthesisKey: synthesisKey,
                    priority: priority,
                    sequenceNumber: self.nextSequenceNumber,
                    enqueuedAt: ProcessInfo.processInfo.systemUptime,
                    work: work,
                    waiters: [waiter]
                )
                self.pendingQueue.append(req)
                self.sortPendingQueue()
                self.processNextIfNeeded()
            }
        } onCancel: {
            Task {
                await self.detachWaiter(waiterID: waiterID)
            }
        }
    }

    internal func promote(synthesisKey: String, to newPriority: SynthesisPriority) {
        if let idx = pendingQueue.firstIndex(where: { $0.synthesisKey == synthesisKey }) {
            if newPriority > pendingQueue[idx].priority {
                pendingQueue[idx].priority = newPriority
                sortPendingQueue()
            }
        }
    }

    internal func detachWaiter(waiterID: UUID) {
        for i in 0..<pendingQueue.count {
            if let wIdx = pendingQueue[i].waiters.firstIndex(where: { $0.waiterID == waiterID }) {
                let waiter = pendingQueue[i].waiters.remove(at: wIdx)
                waiter.continuation.resume(throwing: CancellationError())
                if pendingQueue[i].waiters.isEmpty {
                    pendingQueue.remove(at: i)
                }
                return
            }
        }
        if var active = activeRequest {
            if let wIdx = active.waiters.firstIndex(where: { $0.waiterID == waiterID }) {
                let waiter = active.waiters.remove(at: wIdx)
                waiter.continuation.resume(throwing: CancellationError())
                activeRequest = active
            }
        }
    }

    /// Cancels ONLY pending requests with priority .optionalReserve.
    /// Retains demand, immediateSuccessor, and nextChapterMandatory pending requests across pause.
    internal func cancelPendingOptionalReserveRequests() {
        var kept: [PendingRequest] = []
        var cancelled: [PendingRequest] = []
        for req in pendingQueue {
            if req.priority == .optionalReserve {
                cancelled.append(req)
            } else {
                kept.append(req)
            }
        }
        pendingQueue = kept
        for req in cancelled {
            for waiter in req.waiters {
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    internal func cancelPendingRequests() {
        let queued = pendingQueue
        pendingQueue.removeAll()
        for req in queued {
            for waiter in req.waiters {
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    internal func cancelAll() {
        cancelPendingRequests()
        if let active = activeRequest {
            activeRequest = nil
            for waiter in active.waiters {
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func sortPendingQueue() {
        pendingQueue.sort {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            } else {
                return $0.sequenceNumber < $1.sequenceNumber
            }
        }
    }

    private func processNextIfNeeded() {
        guard !isProcessing, !pendingQueue.isEmpty else { return }
        isProcessing = true

        Task {
            while !pendingQueue.isEmpty {
                let req = pendingQueue.removeFirst()
                let reqID = UUID()
                let active = ActiveRequest(
                    id: reqID,
                    synthesisKey: req.synthesisKey,
                    enqueuedAt: req.enqueuedAt,
                    work: req.work,
                    waiters: req.waiters
                )
                self.activeRequest = active

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

                    if let currentActive = self.activeRequest, currentActive.id == reqID {
                        for waiter in currentActive.waiters {
                            waiter.continuation.resume(with: .success(measuredResult))
                        }
                    }
                } catch {
                    if let currentActive = self.activeRequest, currentActive.id == reqID {
                        for waiter in currentActive.waiters {
                            waiter.continuation.resume(with: .failure(error))
                        }
                    }
                }

                self.activeRequest = nil
            }
            self.isProcessing = false
        }
    }
}
