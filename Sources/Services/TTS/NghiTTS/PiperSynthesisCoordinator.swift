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
        /// `false` = cấm gộp waiter vào request này (và cấm request này gộp vào request khác).
        /// Dùng cho đường stream: chỉ `onChunkPayload` của waiter đầu tiên được gọi, waiter thứ hai
        /// sẽ mất sạch chunk PCM. Payload của đường stream cũng có `pcmDuration = 0`.
        let allowsCoalescing: Bool
        var priority: SynthesisPriority
        let sequenceNumber: UInt64
        let enqueuedAt: TimeInterval
        let work: @Sendable () async throws -> PiperSynthesisPayload
        var waiters: [Waiter]
    }

    private struct ActiveRequest {
        let id: UUID
        let synthesisKey: String?
        let allowsCoalescing: Bool
        /// Mức ưu tiên hiện hành của request đang chạy. Được nâng khi có waiter ưu tiên cao hơn
        /// gộp vào hoặc khi `promote` gọi tới, nhờ vậy `cancelPendingOptionalReserveRequests`
        /// không bao giờ hủy một tác vụ đã bị đòi bởi `.demand`.
        var priority: SynthesisPriority
        let enqueuedAt: TimeInterval
        /// Handle của tác vụ đang chạy `work`. Giữ lại để hủy được thật sự, thay vì chỉ resume
        /// continuation rồi để ONNX suy luận tiếp một đoạn audio chắc chắn sẽ bị bỏ.
        let workTask: Task<PiperSynthesisPayload, Error>
        var waiters: [Waiter]
    }

    private var pendingQueue: [PendingRequest] = []
    private var activeRequest: ActiveRequest? = nil
    private var isProcessing = false
    private var nextSequenceNumber: UInt64 = 0

    /// Xếp hàng một tác vụ chỉ trả `Data`.
    ///
    /// `allowsCoalescing` không có giá trị mặc định: đường này bọc kết quả thành
    /// `PiperSynthesisPayload(pcmDuration: 0)` nên chia sẻ nó cho một waiter đang cần thời lượng
    /// thật là sai. Caller phải tự khẳng định request của mình có chia sẻ được hay không.
    internal func enqueue(
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String? = nil,
        allowsCoalescing: Bool,
        work: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let payload = try await enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: synthesisKey,
            allowsCoalescing: allowsCoalescing
        ) {
            let data = try await work()
            return PiperSynthesisPayload(data: data, pcmDuration: 0.0)
        }
        return payload.data
    }

    internal func enqueuePayload(
        priority: SynthesisPriority,
        requestID: UUID,
        synthesisKey: String? = nil,
        allowsCoalescing: Bool = true,
        work: @escaping @Sendable () async throws -> PiperSynthesisPayload
    ) async throws -> PiperSynthesisPayload {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let waiter = Waiter(waiterID: waiterID, requestID: requestID, continuation: continuation)

                if let synthesisKey = synthesisKey, allowsCoalescing {
                    if let idx = self.pendingQueue.firstIndex(where: { $0.synthesisKey == synthesisKey && $0.allowsCoalescing }) {
                        self.pendingQueue[idx].waiters.append(waiter)
                        if priority > self.pendingQueue[idx].priority {
                            self.pendingQueue[idx].priority = priority
                            self.sortPendingQueue()
                        }
                        return
                    }
                    if var active = self.activeRequest, active.synthesisKey == synthesisKey, active.allowsCoalescing {
                        active.waiters.append(waiter)
                        // Nâng mức ưu tiên của request đang chạy theo waiter mới: nếu không, một
                        // request vào từ `.optionalReserve` rồi được `.demand` gộp vào vẫn bị coi là
                        // reserve và sẽ bị hủy khi tạm dừng, làm mất đúng chunk đang cần.
                        if priority > active.priority {
                            active.priority = priority
                        }
                        self.activeRequest = active
                        return
                    }
                }

                self.nextSequenceNumber += 1
                let req = PendingRequest(
                    synthesisKey: synthesisKey,
                    allowsCoalescing: allowsCoalescing,
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
        // Request đã vào `activeRequest` cũng phải được nâng: đó là dấu hiệu duy nhất cho biết
        // tác vụ đang chạy hiện đã thuộc diện `.demand` và không được phép hủy khi tạm dừng.
        if var active = activeRequest, active.synthesisKey == synthesisKey, newPriority > active.priority {
            active.priority = newPriority
            activeRequest = active
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
                activeRequest = active
                // Không còn ai chờ kết quả: dừng thật tác vụ đang chạy. Trước đây vòng xử lý vẫn
                // `await work()` tới hết nên ONNX suy luận cho audio chắc chắn bị bỏ (nóng máy), và
                // vì vòng xử lý là tuần tự nên request `.demand` mới phải xếp sau ⇒ khựng tiếng.
                if active.waiters.isEmpty {
                    _ = cancelActiveWork()
                    AppLogger.shared.log("🛑 [PiperCoordinator] Hủy tổng hợp đang chạy vì hết waiter key=\(shortKey(active.synthesisKey))")
                }
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    /// Hủy thật request đang chạy và trả về bản ghi của nó (nếu có).
    ///
    /// Cancel handle của `Task` làm `try Task.checkCancellation()` giữa các chunk trong
    /// `ONNXPiperEngine.synthesizeInternal` ném lỗi, nên engine dừng ở chunk kế tiếp thay vì
    /// chạy hết đoạn. `activeRequest` bị xoá ngay để request mới cùng `synthesisKey` không gộp
    /// vào một tác vụ đang chết. Hàm này **không** resume waiter — mỗi caller tự quyết định
    /// resume ai, tránh resume một continuation hai lần.
    private func cancelActiveWork() -> ActiveRequest? {
        guard let active = activeRequest else { return nil }
        activeRequest = nil
        active.workTask.cancel()
        return active
    }

    private func shortKey(_ key: String?) -> String {
        guard let key = key else { return "nil" }
        return String(key.suffix(8))
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

        // Request reserve đã vào `activeRequest` trước đây thoát được đợt hủy này và vẫn chạy tới
        // hết. Chỉ hủy đúng mức `.optionalReserve`: `.demand`, `.immediateSuccessor` và
        // `.nextChapterMandatory` vẫn phải sống qua lần tạm dừng.
        if let active = activeRequest, active.priority == .optionalReserve {
            if let cancelledActive = cancelActiveWork() {
                AppLogger.shared.log("🛑 [PiperCoordinator] Hủy tổng hợp reserve đang chạy key=\(shortKey(cancelledActive.synthesisKey))")
                for waiter in cancelledActive.waiters {
                    waiter.continuation.resume(throwing: CancellationError())
                }
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
        if let active = cancelActiveWork() {
            AppLogger.shared.log("🛑 [PiperCoordinator] cancelAll hủy tổng hợp đang chạy key=\(shortKey(active.synthesisKey))")
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
                let synthesisStartedAt = ProcessInfo.processInfo.systemUptime

                // Bọc `work` trong một Task riêng để giữ được handle mà hủy. Hủy handle này làm
                // `try Task.checkCancellation()` giữa các chunk trong
                // `ONNXPiperEngine.synthesizeInternal` ném lỗi, engine dừng ở chunk kế tiếp.
                let work = req.work
                let workTask = Task<PiperSynthesisPayload, Error> {
                    try await work()
                }
                self.activeRequest = ActiveRequest(
                    id: reqID,
                    synthesisKey: req.synthesisKey,
                    allowsCoalescing: req.allowsCoalescing,
                    priority: req.priority,
                    enqueuedAt: req.enqueuedAt,
                    workTask: workTask,
                    waiters: req.waiters
                )

                do {
                    // Vẫn chờ tới khi task kết thúc thật, kể cả khi đã hủy: cancel của Swift là
                    // hợp tác, `ORTSession.run` của chunk hiện tại luôn chạy xong. Chờ ở đây giữ
                    // bất biến "chỉ một operation tổng hợp tại một thời điểm".
                    let result = try await workTask.value
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
                    // `activeRequest` đã bị xoá nghĩa là đường hủy đã resume waiter của nó rồi —
                    // không được resume lần thứ hai.
                    if let currentActive = self.activeRequest, currentActive.id == reqID {
                        for waiter in currentActive.waiters {
                            waiter.continuation.resume(with: .failure(error))
                        }
                    }
                }

                if let currentActive = self.activeRequest, currentActive.id == reqID {
                    self.activeRequest = nil
                }
            }
            self.isProcessing = false
        }
    }
}
