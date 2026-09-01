import Combine
import Foundation

/// Projection reader cho màn debug extension: đọc `ExtensionDebugEventHub` (actor) và phát ra state đã
/// sẵn sàng để render. Theo quy ước repo, màn hình mới không có ViewModel riêng — chỉ `@State` trong
/// View cộng một reader như thế này.
///
/// Reader giữ **mọi** event nhận được rồi lọc theo `focusedRunId` thay vì chỉ nhận event của run đang
/// xem: nếu lọc ngay ở stream thì những event phát ra trong khoảng giữa "bấm Run" và "biết runId" sẽ
/// mất, và đó lại đúng là những event đầu tiên (`runStarted`, lỗi compile).
@MainActor
final class ExtensionDebugTraceReader: ObservableObject {
    @Published private(set) var allEvents: [ExtensionDebugEvent] = []
    @Published private(set) var startedRuns: Set<UUID> = []
    @Published var focusedRunId: UUID? = nil

    private static let maxDisplayedEvents = 600
    private var streamTask: Task<Void, Never>?

    var visibleEvents: [ExtensionDebugEvent] {
        guard let focusedRunId else { return allEvents }
        return allEvents.filter { $0.runId == focusedRunId }
    }

    /// Còn đang chạy khi run đã được bấm nhưng chưa có event kết thúc nào.
    var isRunning: Bool {
        guard let focusedRunId, startedRuns.contains(focusedRunId) else { return false }
        return !allEvents.contains {
            $0.runId == focusedRunId && ($0.category == .runFinished || $0.category == .cancelled)
        }
    }

    var errorCount: Int {
        visibleEvents.filter { $0.level == .error }.count
    }

    /// Idempotent: gọi lại từ `.task` của View không tạo stream thứ hai.
    func attach(hub: ExtensionDebugEventHub = .shared) {
        guard streamTask == nil else { return }
        // `Task` khởi tạo trong ngữ cảnh `@MainActor` nên thân nó cũng chạy trên MainActor: không cần
        // `MainActor.run` quanh `append`.
        streamTask = Task { [weak self] in
            let stream = await hub.stream()
            for await event in stream {
                guard let self else { return }
                self.append(event)
            }
        }
    }

    func detach() {
        streamTask?.cancel()
        streamTask = nil
    }

    func markStarted(runId: UUID) {
        startedRuns.insert(runId)
        focusedRunId = runId
    }

    func clear() {
        allEvents.removeAll()
        startedRuns.removeAll()
        focusedRunId = nil
    }

    private func append(_ event: ExtensionDebugEvent) {
        allEvents.append(event)
        if allEvents.count > Self.maxDisplayedEvents {
            allEvents.removeFirst(allEvents.count - Self.maxDisplayedEvents)
        }
    }
}
