import Combine
import Foundation
import Observation
import UIKit

/// **Tự tạo bản cặp cho đọc lai** (1.3.938, anh Bửu duyệt): giọng đang chọn chưa có bản ở model kia mà công tắc đọc lai
/// **dùng tới cặp** đang bật ⇒ tạo bản đó qua đúng đường "Tạo bản Nano / Turbo" (`VieNeuVoiceCopyRunner`, kể cả đọc mẫu
/// bằng tiếng máy cho giọng không có mẫu gốc). Xong ⇒ cặp có ngay, đoạn kế tiếp đọc lai. Chưa có cặp thì đọc như cũ.
///
/// - **Công tắc dùng tới cặp**: giọng Nano ⇒ A "Tiếng nước ngoài đọc bằng Turbo" (cần bản Turbo); giọng Turbo ⇒ B "Máy nóng
///   thì đọc bằng Nano" (cần bản Nano). Hai trường hợp kia cặp không bao giờ được dùng ⇒ không tạo.
/// - **Lúc kích hoạt**: **chủ động gạt** công tắc dùng tới cặp sang bật (`switchChanged(_:isOn:)`, từ View; gạt công tắc
///   kia không tính), hoặc **người dùng chọn giọng** ở sheet chọn giọng trong lúc công tắc đang bật (`voiceSelectedByUser()`).
///   Giọng do app tự đổi (mở app, lùi model khi thiếu file, xoá giọng, chọn giọng vừa nhân bản) **không** tính — vì vậy không
///   theo `TTSManager.$selectedVoice`.
/// - **Thiếu file của model kia**: gạt công tắc ⇒ hỏi ("Tải và tạo" / "Bỏ qua", `State.needsDownload`); chỉ đổi giọng
///   (công tắc bật sẵn) ⇒ không hỏi, chỉ log. Không bao giờ tự tải ngầm.
/// - **Một lần mỗi giọng**: giọng đã thử (bắt đầu tạo, lỗi, bấm Bỏ qua) nhớ ở `triedKey`; đổi giọng không tự thử lại. Gạt
///   công tắc là thao tác chủ động nên vẫn xét lại; "Thử lại" ở dòng lỗi chạy tay.
/// - **Chỉ tiền cảnh, không giành tiếng**: app ở nền / truyện đang đọc / đang có lượt tạo khác ⇒ chờ (`State.waiting`), chạy
///   khi app mở lại hoặc truyện dừng. Đang tạo mà app vào nền / truyện bắt đầu đọc ⇒ runner dừng ở bước kế (`canContinue`),
///   không tính là đã thử, chờ như trên.
///
/// Trạng thái hiện ở mục "Đọc lai Nano · Turbo" (`VieNeuHybridSettingsSection`); kết quả là toast của runner; log
/// `🔀 [VieNeuHybrid]`.
@MainActor
@Observable
final class VieNeuHybridPairProvisioner {
    static let shared = VieNeuHybridPairProvisioner()

    enum State: Equatable {
        case idle
        case waiting(VieNeuVoiceCopySource)
        case needsDownload(VieNeuVoiceCopySource, bytes: Int64)
        case running(VieNeuVoiceCopySource)
        case failed(VieNeuVoiceCopySource, message: String)
    }

    enum Switch {
        /// A — "Tiếng nước ngoài đọc bằng Turbo" (giọng Nano cần bản Turbo).
        case language
        /// B — "Máy nóng thì đọc bằng Nano" (giọng Turbo cần bản Nano).
        case thermal
    }

    private enum Trigger {
        case switchTurnedOn
        case voiceChange
    }

    static let triedKey = "vieneuHybridAutoPairTried"

    private(set) var state: State = .idle
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var selectionTask: Task<Void, Never>?

    private init() {}

    /// Gọi một lần lúc mở app (`MainTabView`): chỉ theo dõi để chạy lại việc đang chờ (truyện dừng đọc / app mở lại), không
    /// tự xét giọng nào. Gọi lại vô hại.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        TTSManager.shared.$isPlaying
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resumeWaiting() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resumeWaiting() }
            .store(in: &cancellables)
    }

    // MARK: - Từ View (mục Đọc lai, sheet chọn giọng)

    /// Người dùng vừa chọn giọng ở sheet chọn giọng (`VieNeuVoicePickerSheet.select`). Xét sau 0,8 s để trình đọc đổi model
    /// xong; chọn liên tiếp thì chỉ xét giọng cuối.
    func voiceSelectedByUser() {
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.check(.voiceChange)
        }
    }

    /// Công tắc A / B đổi. Chỉ công tắc dùng tới cặp của model đang đọc mới tính: bật ⇒ xét tạo (hỏi tải nếu thiếu file);
    /// tắt ⇒ bỏ lời hỏi / việc chờ (lượt đang chạy thì chạy nốt).
    func switchChanged(_ which: Switch, isOn: Bool) {
        let relevant: Switch = VieNeuModelChoice.current == .nano ? .language : .thermal
        guard which == relevant else { return }
        if isOn {
            check(.switchTurnedOn)
        } else if !isRunning {
            state = .idle
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// "Tải và tạo bản …" ở dòng hỏi.
    func downloadAndCreate() {
        guard case .needsDownload(let source, _) = state else { return }
        begin(source)
    }

    /// "Bỏ qua giọng này" — nhớ là đã thử, không hỏi lại khi đổi giọng.
    func skip() {
        guard case .needsDownload(let source, _) = state else { return }
        markTried(source)
        AppLogger.shared.log("🔀 [VieNeuHybrid] Bỏ qua tạo bản \(source.target.label) cho \(source.id)")
        state = .idle
    }

    /// "Thử lại" ở dòng lỗi.
    func retry() {
        guard case .failed(let source, _) = state else { return }
        begin(source)
    }

    // MARK: - Nội bộ

    private func check(_ trigger: Trigger) {
        guard !isRunning else { return }
        let directory = VieNeuVoiceDirectory.shared
        if !directory.hasLoaded {
            // Danh sách giọng chưa đọc đĩa lần nào (chưa mở sheet chọn giọng) ⇒ đọc rồi xét lại một lần.
            directory.reload()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard VieNeuVoiceDirectory.shared.hasLoaded else { return }
                self?.check(trigger)
            }
            return
        }
        guard let source = candidate() else {
            // Giọng mới đã có cặp / công tắc dùng tới cặp đã tắt ⇒ bỏ lời hỏi / việc chờ của giọng cũ.
            state = .idle
            return
        }
        if trigger == .voiceChange, isTried(source) {
            if state != .waiting(source) { state = .idle }
            return
        }
        let missing = VieNeuClonePackages.missingBytes(nano: source.target == .nano, turbo: source.target == .turbo)
        guard missing == 0 else {
            if trigger == .switchTurnedOn {
                state = .needsDownload(source, bytes: missing)
                AppLogger.shared.log("🔀 [VieNeuHybrid] \(source.id) chưa có bản \(source.target.label), thiếu \(missing / 1_000_000) MB ⇒ hỏi tải")
            } else {
                state = .idle
                AppLogger.shared.log("🔀 [VieNeuHybrid] \(source.id) chưa có bản \(source.target.label), thiếu \(missing / 1_000_000) MB ⇒ không tự tạo (công tắc bật sẵn)")
            }
            return
        }
        begin(source)
    }

    /// Giọng đang chọn, công tắc dùng tới cặp đang bật, chưa có cặp, đã tải đủ để đọc ⇒ nguồn nhân bản.
    private func candidate() -> VieNeuVoiceCopySource? {
        let tts = TTSManager.shared
        guard tts.tool == "vieneu", !tts.selectedVoice.isEmpty else { return nil }
        let model = VieNeuModelChoice.current
        let switchOn = model == .nano ? VieNeuHybridSettings.isLanguageRoutingEnabled : VieNeuHybridSettings.isThermalRoutingEnabled
        guard switchOn, VieNeuVoicePairing.shared.pair(model: model, voice: tts.selectedVoice) == nil else { return nil }
        let directory = VieNeuVoiceDirectory.shared
        guard let entry = directory.entry(for: VieNeuVoiceSelection(model: model, voiceId: tts.selectedVoice)),
              directory.isReady(entry) else { return nil }
        return directory.copySource(for: entry)
    }

    private func begin(_ source: VieNeuVoiceCopySource) {
        guard Self.isClearToRun() else {
            state = .waiting(source)
            AppLogger.shared.log("🔀 [VieNeuHybrid] Chờ tạo bản \(source.target.label) cho \(source.id) (app ở nền / truyện đang đọc / đang có lượt tạo khác)")
            return
        }
        markTried(source)
        state = .running(source)
        let reason = VieNeuVoiceCopyRunner.shared.run(
            source,
            automatic: true,
            canContinue: { Self.isClearToRun(ignoringRunner: true) },
            onFinish: { [weak self] outcome in self?.finish(source, outcome: outcome) }
        )
        if let reason {
            state = .failed(source, message: reason)
            AppLogger.shared.log("❌ [VieNeuHybrid] Không tự tạo được bản \(source.target.label) cho \(source.id): \(reason)")
        }
    }

    private func finish(_ source: VieNeuVoiceCopySource, outcome: VieNeuVoiceCopyRunner.Outcome) {
        if outcome.wasPaused {
            unmarkTried(source)
            state = .waiting(source)
        } else if outcome.succeeded {
            state = .idle
            // Cặp vừa có ⇒ engine của trình đọc đổi sang engine bọc từ đoạn kế tiếp (bỏ audio nạp trước, chuẩn bị lại).
            TTSManager.shared.vieNeuHybridSettingsDidChange()
            AppLogger.shared.log("🔀 [VieNeuHybrid] Đã tạo bản \(source.target.label) cho \(source.id) ⇒ đọc lai bật")
        } else {
            state = .failed(source, message: outcome.message)
        }
    }

    /// App mở lại / truyện dừng đọc ⇒ chạy việc đang chờ, nếu giọng đang chọn vẫn là giọng đó.
    private func resumeWaiting() {
        guard case .waiting(let source) = state else { return }
        guard let current = candidate(), current.id == source.id else {
            state = .idle
            return
        }
        begin(current)
    }

    /// App ở tiền cảnh, truyện không đọc, (và không có lượt tạo khác).
    private static func isClearToRun(ignoringRunner: Bool = false) -> Bool {
        UIApplication.shared.applicationState == .active
            && !TTSManager.shared.isPlaying
            && (ignoringRunner || !VieNeuVoiceCopyRunner.shared.isRunning)
    }

    // MARK: - Giọng đã thử

    private func isTried(_ source: VieNeuVoiceCopySource) -> Bool {
        triedKeys.contains(source.id)
    }

    private func markTried(_ source: VieNeuVoiceCopySource) {
        var keys = triedKeys
        guard !keys.contains(source.id) else { return }
        keys.append(source.id)
        UserDefaults.standard.set(keys, forKey: Self.triedKey)
    }

    private func unmarkTried(_ source: VieNeuVoiceCopySource) {
        UserDefaults.standard.set(triedKeys.filter { $0 != source.id }, forKey: Self.triedKey)
    }

    private var triedKeys: [String] {
        UserDefaults.standard.stringArray(forKey: Self.triedKey) ?? []
    }
}
