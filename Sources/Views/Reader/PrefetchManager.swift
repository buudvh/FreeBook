import Foundation

actor PrefetchManager {
    private let maxConcurrentRequests = 2
    private var queue: [Int] = []
    private var activeTasks: [Int: Task<Void, Never>] = [:]
    
    typealias FetchBlock = (Int) async throws -> Void
    
    // Đồng bộ hàng đợi theo cửa sổ hiển thị mới và hủy bỏ các task cũ ngoài window
    func updateQueue(withVisibleIndexes indexes: Set<Int>, fetcher: @escaping FetchBlock) async {
        // 1. Hủy bỏ và loại bỏ các tác vụ đang chạy nằm ngoài cửa sổ mới
        let tasksToCancel = activeTasks.filter { !indexes.contains($0.key) }
        for (idx, task) in tasksToCancel {
            task.cancel()
            activeTasks.removeValue(forKey: idx)
            #if DEBUG
            AppLogger.shared.log("🚫 [PrefetchManager] Hủy tác vụ tải trước lỗi thời của chương \(idx)")
            #endif
        }
        
        // 2. Loại bỏ các index đang chờ trong hàng đợi nằm ngoài cửa sổ mới
        queue = queue.filter { indexes.contains($0) }
        
        // 3. Thêm các index mới trong cửa sổ vào hàng đợi
        for idx in indexes {
            if !queue.contains(idx) && activeTasks[idx] == nil {
                queue.append(idx)
            }
        }
        
        // 4. Kích hoạt xử lý hàng đợi
        await processQueue(fetcher: fetcher)
    }
    
    private func processQueue(fetcher: @escaping FetchBlock) async {
        guard activeTasks.count < maxConcurrentRequests, !queue.isEmpty else { return }
        
        let nextIndex = queue.removeFirst()
        
        let task = Task {
            do {
                try await fetcher(nextIndex)
            } catch {
                #if DEBUG
                AppLogger.shared.log("⚠️ [PrefetchManager] Tải thất bại chương \(nextIndex): \(error.localizedDescription)")
                #endif
            }
            await self.taskCompleted(nextIndex, fetcher: fetcher)
        }
        activeTasks[nextIndex] = task
        
        // Gọi đệ quy lấp đầy worker
        await processQueue(fetcher: fetcher)
    }
    
    private func taskCompleted(_ index: Int, fetcher: @escaping FetchBlock) async {
        activeTasks.removeValue(forKey: index)
        await processQueue(fetcher: fetcher)
    }
    
    func cancelAll() {
        queue.removeAll()
        for task in activeTasks.values { task.cancel() }
        activeTasks.removeAll()
    }
}
