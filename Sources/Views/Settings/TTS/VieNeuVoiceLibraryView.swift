import AVFoundation
import SwiftUI

/// Màn **"Giọng của tôi"** — quản lý giọng nhân bản của VieNeu-TTS v3 Nano.
///
/// Giọng nhân bản **không phải file model**: nó là hai mảng số (x-vector 192 + style 12.800) cộng một
/// file audio mẫu giữ lại để nghe lại và tạo lại embedding. Vì vậy màn này quản lý **dữ liệu**, còn gói
/// graph (~91 MB) chỉ là điều kiện cần để **tạo** giọng — tải một lần, dùng cho mọi giọng về sau.
///
/// ## Vì sao màn riêng thay vì thêm thẳng vào màn thử giọng
/// Màn thử giọng đã 377 dòng và lo việc *đo RTF*; nhồi thêm luồng thu âm + `fileImporter` + danh sách
/// giọng vào đó là vượt trần 400 dòng **và** trộn hai mục đích. Đây là cùng cách đã tách
/// `VieNeuTTSTestView+Sections`.
///
/// ## Nút bấm ở đây **không** dùng `.borderedProminent`
/// `MainTabView` đặt `.tint(.white)` toàn cục, mà `.borderedProminent` không tự đảo màu chữ theo tint ⇒
/// nút thành nền trắng chữ trắng (bug đã gặp ở 1.3.447). Dùng `Button` + `Label` trong `Form` như màn thử
/// giọng để không phải nhớ cái bẫy đó.
struct VieNeuVoiceLibraryView: View {
    /// Câu dùng cho "Nghe giọng" — cùng câu với màn thử giọng để hai chỗ nghe ra giống nhau.
    static let previewText = "Xin chào, đây là bản thử giọng đọc VieNeu-TTS."

    @State var records: [VieNeuCustomVoiceStore.Record] = []
    @State var statusMessage = ""
    @State var isError = false
    @State var isDownloading = false
    @State var downloadProgress: Double = 0
    @State var downloadMessage = ""
    @State var isWorking = false
    @State var workingMessage = ""
    @State var showingCreator = false
    @State var player: AVAudioPlayer?
    @State var playingVoiceID: String?
    @State var renamingID: String?
    @State var renameText = ""
    @State var pendingDeletion: VieNeuCustomVoiceStore.Record?
    @State var workTask: Task<Void, Never>?
    /// Bước hiện tại của lượt nhân bản. Xem `EnrollProgress` ở file `+Sections`.
    @StateObject var enrollProgress = EnrollProgress()

    var service: VieNeuTTSService? { VieNeuTTSService.shared }
    var store: VieNeuCustomVoiceStore? { service?.customVoiceStore }
    var hasCloneGraphs: Bool { service?.hasCloneGraphs ?? false }
    var isModelReady: Bool { service?.modelStore.isReady ?? false }

    /// Nhân bản dùng chung phiên âm thanh với TTS: vừa nghe thử vừa đọc truyện là hai đường tranh nhau.
    var isBlockedByPlayback: Bool {
        TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget
    }

    /// Lý do chặn do **đang phát lại**; `nil` = không chặn. Tách khỏi `isBlockedByPlayback` vì hai
    /// nguyên nhân cần **hai câu thông báo khác nhau**: `isPlaying` là đang đọc truyện, còn
    /// `showFloatingWidget` là trình phát đang hiện nhưng có thể đã tạm dừng.
    ///
    /// `action` là việc người dùng đang muốn làm ("tạo giọng" / "nghe thử") để câu thông báo khớp.
    /// Nút bị `.disabled` **không** phát sinh sự kiện, nên hai nút dưới đây đã bỏ cổng này khỏi
    /// `.disabled` và kiểm ở đầu action để báo được bằng toast.
    func playbackBlockReason(action: String = "tạo giọng") -> String? {
        if TTSManager.shared.isPlaying { return "Đang phát truyện. Dừng phát rồi \(action)." }
        if TTSManager.shared.showFloatingWidget { return "Đang mở trình phát TTS. Đóng trình phát rồi \(action)." }
        return nil
    }

    var body: some View {
        Form {
            clonePackageSection
            voiceListSection
            creationSection

            if !statusMessage.isEmpty {
                Section("Kết quả") {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(isError ? Color.red : Color.secondary)
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Bản Nano cho chất lượng nhân bản thấp hơn bản Turbo. Thu âm ở nơi yên tĩnh, 3–8 giây, một người nói — audio mẫu càng sạch thì giọng nhân bản càng giống.")
            }
        }
        .tint(.white)
        .navigationTitle("Giọng của tôi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onDisappear(perform: teardown)
        .sheet(isPresented: $showingCreator) {
            VieNeuVoiceCreatorView(
                onSave: { name, url in
                    showingCreator = false
                    enroll(name: name, sampleURL: url, replacing: nil)
                },
                onCancel: { showingCreator = false }
            )
        }
        .confirmationDialog(
            "Xoá giọng “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Xoá giọng và audio mẫu", role: .destructive) {
                if let record = pendingDeletion { delete(record) }
                pendingDeletion = nil
            }
            Button("Huỷ", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Audio mẫu đã lưu cũng bị xoá. Không khôi phục được.")
        }
        .alert(
            "Đổi tên giọng",
            isPresented: Binding(
                get: { renamingID != nil },
                set: { if !$0 { renamingID = nil } }
            )
        ) {
            TextField("Tên giọng", text: $renameText)
            Button("Lưu") { commitRename() }
            Button("Huỷ", role: .cancel) { renamingID = nil }
        } message: {
            Text("Tên mới phải khác các giọng đang có.")
        }
    }

    // MARK: - Hành động

    func reload() {
        records = (store?.loadLeniently() ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func teardown() {
        workTask?.cancel()
        workTask = nil
        stopPlayback()
        isWorking = false
    }

    func downloadCloneGraphs() {
        guard let service else { return }
        isDownloading = true
        isError = false
        statusMessage = ""
        let client = VieNeuModelClient(store: service.modelStore)
        Task {
            do {
                _ = try await client.prefetchCloneGraphs { message, fraction in
                    Task { @MainActor in
                        downloadMessage = message
                        downloadProgress = fraction
                    }
                }
                isDownloading = false
                statusMessage = "Đã tải xong gói graph nhân bản."
            } catch {
                isDownloading = false
                isError = true
                statusMessage = "Tải gói graph thất bại: \(error.localizedDescription)"
            }
        }
    }

    /// Xoá **chỉ 3 graph clone** — không đụng 4 graph chính lẫn giọng đã tạo. Giọng đã tạo vẫn nghe được
    /// sau khi xoá gói graph; chỉ **tạo mới / tạo lại embedding** là cần tải lại.
    func deleteCloneGraphs() {
        guard let service else { return }
        do {
            try service.modelStore.deleteCloneGraphs()
            isError = false
            statusMessage = "Đã xoá gói graph nhân bản."
        } catch {
            isError = true
            statusMessage = "Xoá gói graph thất bại: \(error.localizedDescription)"
        }
    }

    /// Nhân bản rồi lưu. `replacing` khác `nil` ⇒ ghi đè hai mảng số của giọng đó (đường "Tạo lại
    /// embedding" — dùng lại `samples/<uuid>` đã lưu, **không** thu lại).
    func enroll(name: String, sampleURL: URL, replacing: VieNeuCustomVoiceStore.Record?) {
        guard let service else { return }
        guard !isBlockedByPlayback else {
            isError = true
            statusMessage = "Đang đọc truyện — dừng TTS trước khi tạo giọng, vì hai bên dùng chung phiên âm thanh."
            return
        }
        stopPlayback()
        isWorking = true
        isError = false
        workingMessage = "Đang phân tích audio mẫu…"
        enrollProgress.stage = nil
        statusMessage = ""

        workTask = Task {
            do {
                // **Không** nạp engine chính ở đây. `enrollVoice` chỉ dùng `modelStore` + `VieNeuVoiceCloner`
                // (nó mở ngữ cảnh ORT riêng cho 3 graph clone), nên nạp thêm 4 graph + 62,8 MB `sea_g2p.bin`
                // là chi phí **thừa** — đây chính là phần "bấm Tạo giọng chờ lâu". Engine chính được nạp ở
                // `playPreview` khi người dùng thực sự cần nghe.
                workingMessage = "Đang nhân bản giọng…"
                // Closure này là `@Sendable` (chạy trong `Task.detached` của `enrollVoice`) nên **không**
                // được capture `self` — chỉ capture hộp `progress`, xem `EnrollProgress`.
                let progress = enrollProgress
                let enrollment = try await service.enrollVoice(sampleURL: sampleURL) { stage in
                    Task { @MainActor in progress.stage = stage }
                }
                guard !Task.isCancelled else { return }

                let store = service.customVoiceStore
                if let replacing {
                    try store.update(
                        id: replacing.id,
                        speakerEmbedding: enrollment.speakerEmbedding,
                        style: enrollment.style
                    )
                } else {
                    _ = try store.add(
                        name: name,
                        speakerEmbedding: enrollment.speakerEmbedding,
                        style: enrollment.style,
                        sampleSourceURL: sampleURL
                    )
                }
                // `add` đã **copy** audio mẫu vào `CustomVoices/samples/` ⇒ dọn file tạm của bản thu.
                discardTemporarySample(sampleURL)
                isWorking = false
                isError = false
                statusMessage = replacing == nil
                    ? "Đã tạo giọng “\(name)” từ \(String(format: "%.1f", enrollment.sampleSeconds)) giây audio."
                    : "Đã tạo lại embedding cho “\(name)”."
                reload()
                refreshVoiceCatalog()
            } catch is CancellationError {
                isWorking = false
            } catch {
                isWorking = false
                isError = true
                statusMessage = "Tạo giọng thất bại: \(error.localizedDescription)"
            }
        }
    }

    /// Nạp lại catalog giọng của engine sau khi kho giọng đổi (tạo / tạo lại / đổi tên / xoá).
    ///
    /// **Bắt buộc**: `VieNeuTTSEngine.prepareLocked` chỉ nạp catalog **một lần** trong vòng đời engine
    /// (`VieNeuTTSEngine.swift:150`), mà engine sống suốt vòng đời app. Thiếu bước này thì giọng vừa tạo bị
    /// `synthesize` rơi **im lặng** về giọng mặc định cho tới khi mở lại app — đã xảy ra thật: tạo giọng
    /// xong đọc truyện nghe y giọng mặc định, tắt app mở lại mới đúng âm sắc.
    ///
    /// Lỗi ở đây **không** được làm hỏng kết quả đã đạt được (giọng đã lưu xong), nên chỉ ghi chú thêm.
    func refreshVoiceCatalog() {
        do {
            try service?.refreshVoiceCatalog()
        } catch {
            statusMessage += " (Chưa nạp lại được danh sách giọng: \(error.localizedDescription))"
        }
    }

    func delete(_ record: VieNeuCustomVoiceStore.Record) {
        guard let store else { return }
        do {
            try store.delete(id: record.id)
            if playingVoiceID == record.id { stopPlayback() }
            isError = false
            statusMessage = "Đã xoá giọng “\(record.name)”."
            reload()
            refreshVoiceCatalog()
        } catch {
            isError = true
            statusMessage = "Xoá thất bại: \(error.localizedDescription)"
        }
    }

    func commitRename() {
        guard let store, let id = renamingID else { return }
        let name = renameText
        renamingID = nil
        do {
            try store.rename(id: id, to: name)
            isError = false
            statusMessage = "Đã đổi tên giọng thành “\(name.trimmed)”."
            reload()
            refreshVoiceCatalog()
        } catch {
            isError = true
            statusMessage = "Đổi tên thất bại: \(error.localizedDescription)"
        }
    }

    /// Tạo lại embedding từ **audio mẫu đã lưu** — không cần thu lại, và cũng là cách kiểm chứng rằng
    /// bản thu cũ vẫn dùng được sau khi đổi engine/thuật toán.
    func reEnroll(_ record: VieNeuCustomVoiceStore.Record) {
        guard let store, let sampleURL = store.sampleURL(for: record) else {
            isError = true
            statusMessage = "Giọng này không còn audio mẫu để tạo lại."
            return
        }
        enroll(name: record.name, sampleURL: sampleURL, replacing: record)
    }

    /// Nghe thử **giọng nhân bản** qua đúng đường tổng hợp của Reader.
    func playPreview(_ record: VieNeuCustomVoiceStore.Record) {
        guard let service else { return }
        guard !isBlockedByPlayback else {
            isError = true
            statusMessage = "Đang đọc truyện — dừng TTS trước khi nghe thử."
            return
        }
        stopPlayback()
        isError = false
        statusMessage = "Đang tạo bản nghe thử cho “\(record.name)”…"

        workTask = Task {
            do {
                if !service.isPrepared { try await service.prepare(voice: record.name) }
                let result = try await service.synthesizeWithDuration(
                    text: Self.previewText,
                    voice: record.name,
                    speed: 1.0,
                    boundaryKind: .paragraphEnd,
                    priority: .demand
                )
                guard !Task.isCancelled else { return }
                statusMessage = "Nghe thử “\(record.name)”."
                play(result.data, voiceID: record.id)
            } catch is CancellationError {
            } catch {
                isError = true
                statusMessage = "Nghe thử thất bại: \(error.localizedDescription)"
            }
        }
    }

    /// Nghe lại **audio mẫu gốc** — để đối chiếu khi giọng nhân bản nghe không giống.
    func playSample(_ record: VieNeuCustomVoiceStore.Record) {
        guard let store, let url = store.sampleURL(for: record) else {
            isError = true
            statusMessage = "Giọng này không còn audio mẫu."
            return
        }
        stopPlayback()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            player = newPlayer
            playingVoiceID = record.id
            newPlayer.prepareToPlay()
            newPlayer.play()
            isError = false
            statusMessage = "Đang phát audio mẫu của “\(record.name)”."
        } catch {
            isError = true
            statusMessage = "Phát audio mẫu thất bại: \(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingVoiceID = nil
    }

    /// Dọn file audio mẫu **trong thư mục tạm** sau khi nó đã được copy vào kho.
    ///
    /// Chỉ đụng file trong `temporaryDirectory`: đường "Tạo lại embedding" truyền vào chính file trong
    /// `CustomVoices/samples/`, xoá nó là mất luôn audio mẫu của giọng.
    private func discardTemporarySample(_ url: URL) {
        guard url.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func play(_ data: Data, voiceID: String) {
        do {
            let newPlayer = try AVAudioPlayer(data: data)
            player = newPlayer
            playingVoiceID = voiceID
            newPlayer.prepareToPlay()
            newPlayer.play()
        } catch {
            isError = true
            statusMessage = "Phát thất bại: \(error.localizedDescription)"
        }
    }
}
