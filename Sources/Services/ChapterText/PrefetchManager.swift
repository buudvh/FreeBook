import Foundation

actor PrefetchManager {
    private actor ReaderPrefetchGate {
        static let shared = ReaderPrefetchGate(limit: 2)

        private let limit: Int
        private var activeCount = 0

        init(limit: Int) {
            self.limit = limit
        }

        func acquire() async throws {
            while activeCount >= limit {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            try Task.checkCancellation()
            activeCount += 1
        }

        func release() {
            activeCount = max(0, activeCount - 1)
        }
    }
    private let maxConcurrentRequests = 2
    private var queue: [Int] = []
    private var activeTasks: [Int: Task<Void, Never>] = [:]
    
    typealias FetchBlock = (Int) async throws -> Void
    
    func updateQueue(withVisibleIndexes indexes: Set<Int>, activeIndex: Int, fetcher: @escaping FetchBlock) async {
        let tasksToCancel = activeTasks.filter { !indexes.contains($0.key) }
        for (idx, task) in tasksToCancel {
            task.cancel()
            #if DEBUG
            AppLogger.shared.log("🚫 [PrefetchManager] Hủy tác vụ tải trước lỗi thời của chương \(idx)")
            #endif
        }
        
        queue = queue.filter { indexes.contains($0) }
        
        if indexes.contains(activeIndex) {
            if !queue.contains(activeIndex) && activeTasks[activeIndex] == nil {
                queue.insert(activeIndex, at: 0)
            } else if let pos = queue.firstIndex(of: activeIndex) {
                queue.remove(at: pos)
                queue.insert(activeIndex, at: 0)
            }
        }
        
        for idx in indexes {
            if idx != activeIndex {
                if !queue.contains(idx) && activeTasks[idx] == nil {
                    queue.append(idx)
                }
            }
        }
        
        await processQueue(fetcher: fetcher)
    }
    
    private func processQueue(fetcher: @escaping FetchBlock) async {
        guard activeTasks.count < maxConcurrentRequests, !queue.isEmpty else { return }
        
        let nextIndex = queue.removeFirst()
        
        let task = Task {
            do {
                try await ReaderPrefetchGate.shared.acquire()
                do {
                    try await fetcher(nextIndex)
                    await ReaderPrefetchGate.shared.release()
                } catch {
                    await ReaderPrefetchGate.shared.release()
                    throw error
                }
            } catch is CancellationError {
            } catch {
                #if DEBUG
                AppLogger.shared.log("⚠️ [PrefetchManager] Tải thất bại chương \(nextIndex): \(error.localizedDescription)")
                #endif
            }
            await self.taskCompleted(nextIndex, fetcher: fetcher)
        }
        activeTasks[nextIndex] = task
        
        await processQueue(fetcher: fetcher)
    }
    
    private func taskCompleted(_ index: Int, fetcher: @escaping FetchBlock) async {
        activeTasks.removeValue(forKey: index)
        await processQueue(fetcher: fetcher)
    }
    
    func cancelAll() {
        queue.removeAll()
        for task in activeTasks.values { task.cancel() }
    }
}
