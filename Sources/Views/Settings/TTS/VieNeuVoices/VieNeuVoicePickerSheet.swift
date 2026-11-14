import SwiftUI

/// **Sheet chọn giọng VieNeu** (1.3.900, mockup anh Bửu duyệt): chip "Nano | Turbo" (mở ra chọn sẵn model đang dùng),
/// rồi "Giọng của tôi" (giọng nhân bản của model đó), rồi Turbo "Tuyển chọn" + "Giọng khác" / Nano "Giọng có sẵn".
///
/// - Không có dòng tải model riêng: mỗi giọng có nút ⬇ của nó. Nano tải chung một gói ⇒ bấm ⬇ một giọng Nano thì **mọi**
///   hàng Nano cùng hiện tiến độ; Turbo tải model nếu thiếu rồi file của đúng giọng đó ⇒ tiến độ chỉ ở hàng đó.
/// - Chọn giọng = `TTSManager.selectVieNeuVoice` ⇒ model đi theo giọng (khác model thì trình đọc nạp lại engine).
/// - Thử giọng qua `VieNeuVoicePreviewPlayer`; sheet đóng thì dừng câu thử.
/// - Nhấn giữ giọng nhân bản ⇒ Đổi tên / Xoá (thay màn "Giọng của tôi" cũ). Giọng Turbo tải về đã có file ⇒ nút 🗑 cuối
///   hàng xoá file của riêng giọng đó (`VieNeuModelDataRemover.deleteTurboVoice`, model giữ lại). Giọng Nano có sẵn dùng
///   chung một gói nên không có nút riêng; xoá cả gói Nano / Turbo ở trang Cài đặt VieNeu TTS ("Xoá tất cả dữ liệu …").
/// - Ô tìm theo tên giọng (`VoiceNameSearch`: bỏ dấu, "đ" = "d") lọc trong chip đang chọn; đang tìm thì ẩn hàng
///   "Nhân bản giọng đọc", nhóm không còn giọng nào khớp thì ẩn cả nhóm.
/// - Hàng đầu "Nhân bản giọng đọc" ⇒ `VieNeuVoiceCloneSheet` (1.3.901).
/// - Nhân bản chéo (1.3.937, `VieNeuVoiceCopyRunner`): nhấn giữ giọng chưa có bản ở model kia ⇒ "Tạo bản Turbo / Nano"
///   (`VieNeuVoiceRowMenu`); giọng tự tạo chưa có bản ở model kia hiện trong "Giọng của tôi" của chip đích với nút
///   (`VieNeuVoiceCopyRow`). Không có mẫu gốc ⇒ hỏi trước (tạo từ tiếng máy đọc). Bắt đầu ⇒ sheet sang chip đích; lượt
///   của giọng có sẵn hiện tạm một hàng tiến độ ở đó. Kết quả báo bằng toast từ runner.
struct VieNeuVoicePickerSheet: View {
    static let helpText: [LocalizedStringKey] = [
        "Nhẹ: Nano, khoảng 29 CPU-giây mỗi 1.000 ký tự. Vừa: Turbo, 37–43 (đo Minh Quân Pro, Mai Anh). Nặng: Turbo có mẫu dài, ước tính. Đo trên iPhone 11.",
        "Tạo bản Nano / Turbo: nhấn giữ một giọng chưa có bản ở model kia. Có mẫu gốc thì nhân bản từ mẫu; không có thì app cho giọng đó đọc một đoạn khoảng 15 giây rồi nhân bản từ tiếng máy đọc, nên có thể kém giống hơn. Bản mới được ghép cặp cho chế độ đọc lai Nano · Turbo."
    ]

    @ObservedObject private var downloads = ModelDownloadCenter.shared
    @ObservedObject private var ttsManager = TTSManager.shared
    @State private var model: VieNeuModelChoice = VieNeuModelChoice.current
    @State private var renaming: VieNeuVoiceEntry?
    @State private var renameText = ""
    @State private var pendingDeletion: VieNeuVoiceEntry?
    @State private var pendingTurboVoiceDeletion: VieNeuVoiceEntry?
    @State private var isClonePresented = false
    @State private var pendingSpokenCopy: VieNeuVoiceCopySource?
    @State private var query = ""

    private var directory: VieNeuVoiceDirectory { .shared }
    private var preview: VieNeuVoicePreviewPlayer { .shared }

    var body: some View {
        // Giọng trình đọc đang dùng — tính **một lần** mỗi lượt vẽ (`VieNeuModelChoice.current` kiểm file GGUF), không
        // theo từng hàng: sheet vẽ lại theo mỗi nhịp tiến độ tải.
        let reader: VieNeuVoiceSelection? = ttsManager.tool == "vieneu"
            ? VieNeuVoiceSelection(model: VieNeuModelChoice.current, voiceId: ttsManager.selectedVoice)
            : nil
        NavigationStack {
            VStack(spacing: 0) {
                VieNeuChipBar(options: [(value: VieNeuModelChoice.nano, title: "Nano"), (value: .turbo, title: "Turbo")], selection: $model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                List {
                    Group {
                        if normalizedQuery.isEmpty {
                            cloneEntryRow
                        }
                        if model == .nano {
                            nanoSections(reader: reader)
                        } else {
                            turboSections(reader: reader)
                        }
                    }
                    .glassSheetRows()
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm theo tên giọng")
            .pageTitle("Giọng đọc", help: Self.helpText)
        }
        .onAppear {
            directory.reload()
            VieNeuCoreMLAccelerator.shared.refresh()
        }
        .onDisappear { preview.finishSession() }
        .onChange(of: preview.failureToken) { _, _ in
            ToastManager.shared.show(message: preview.failureMessage, type: .error)
        }
        .sheet(isPresented: $isClonePresented, onDismiss: { model = VieNeuModelChoice.current }) {
            Group {
                VieNeuVoiceCloneSheet(target: Self.defaultCloneTarget)
                    .presentationDragIndicator(.visible)
            }
            .appGlassSheet()
        }
        .alert("Đổi tên giọng", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên giọng", text: $renameText)
            Button("Lưu") { commitRename() }
            Button("Huỷ", role: .cancel) { renaming = nil }
        } message: {
            Text("Tên mới phải khác các giọng đang có.")
        }
        .confirmationDialog(
            "Xoá giọng “\(pendingTurboVoiceDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingTurboVoiceDeletion != nil },
                set: { if !$0 { pendingTurboVoiceDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Xoá giọng", role: .destructive) { commitTurboVoiceDeletion() }
            Button("Huỷ", role: .cancel) { pendingTurboVoiceDeletion = nil }
        } message: {
            Text("Xoá file của giọng này (model Turbo giữ lại, tải lại bằng nút ⬇).")
        }
        .confirmationDialog(
            "Tạo bản \(pendingSpokenCopy?.target.label ?? "") của “\(pendingSpokenCopy?.name ?? "")”?",
            isPresented: Binding(get: { pendingSpokenCopy != nil }, set: { if !$0 { pendingSpokenCopy = nil } }),
            titleVisibility: .visible
        ) {
            Button("Tạo bản \(pendingSpokenCopy?.target.label ?? "")") {
                if let source = pendingSpokenCopy { launchCopy(source) }
                pendingSpokenCopy = nil
            }
            Button("Huỷ", role: .cancel) { pendingSpokenCopy = nil }
        } message: {
            Text("Giọng này không có mẫu gốc. App cho giọng đọc một đoạn khoảng 15 giây rồi nhân bản từ tiếng đó — bản mới có thể kém giống hơn.")
        }
        .confirmationDialog(
            "Xoá giọng “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá giọng", role: .destructive) { commitDeletion() }
            Button("Huỷ", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Mẫu âm thanh đã lưu của giọng này cũng bị xoá. Không khôi phục được.")
        }
    }

    // MARK: - Nhóm

    /// Hàng đầu danh sách: "Nhân bản giọng đọc" (đũa thần, chữ màu nhấn, chevron) ⇒ sheet nhân bản.
    private var cloneEntryRow: some View {
        Section {
            Button {
                preview.stop()
                isClonePresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36)
                    Text("Nhân bản giọng đọc")
                        .font(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Mặc định "Dùng cho" của sheet nhân bản = model đang đọc.
    private static var defaultCloneTarget: VieNeuVoiceCloneFlow.Target {
        VieNeuModelChoice.current == .turbo ? .turbo : .nano
    }

    private var normalizedQuery: String { VoiceNameSearch.normalize(query) }

    private func filtered(_ entries: [VieNeuVoiceEntry]) -> [VieNeuVoiceEntry] {
        let query = normalizedQuery
        guard !query.isEmpty else { return entries }
        return entries.filter { VoiceNameSearch.matches($0.name, normalizedQuery: query) }
    }

    /// Đang tìm mà chip hiện tại không còn giọng nào khớp.
    private var noMatchSection: some View {
        Section {
            Text("Không có giọng nào tên “\(query.trimmingCharacters(in: .whitespaces))”.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func nanoSections(reader: VieNeuVoiceSelection?) -> some View {
        let mine = filtered(directory.nanoMine)
        let copies = copyRows(target: .nano)
        let presets = filtered(directory.nanoPresets)
        if !mine.isEmpty || !copies.isEmpty {
            Section("Giọng của tôi") {
                rows(mine, reader: reader)
                copyRowViews(copies)
            }
        }
        if !presets.isEmpty {
            Section("Giọng có sẵn") { rows(presets, reader: reader) }
        }
        if mine.isEmpty, copies.isEmpty, presets.isEmpty, !normalizedQuery.isEmpty {
            noMatchSection
        }
    }

    @ViewBuilder
    private func turboSections(reader: VieNeuVoiceSelection?) -> some View {
        if !directory.isTurboRuntimeAvailable {
            Section {
                Text("Bản build này chưa có audio.cpp nên chưa dùng được giọng Turbo.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        let query = normalizedQuery
        let mine = filtered(directory.turboMine)
        let copies = copyRows(target: .turbo)
        let featured = filtered(directory.turboFeatured)
        let others = filtered(directory.turboOthers)
        if !mine.isEmpty || !copies.isEmpty {
            Section("Giọng của tôi") {
                rows(mine, reader: reader)
                copyRowViews(copies)
            }
        }
        if !featured.isEmpty {
            Section("Tuyển chọn") { rows(featured, reader: reader) }
        }
        if !others.isEmpty {
            Section("Giọng khác") { rows(others, reader: reader) }
        }
        if mine.isEmpty, copies.isEmpty, featured.isEmpty, others.isEmpty, !query.isEmpty {
            noMatchSection
        }
    }

    /// Hàng "Tạo bản …" của chip `target`: giọng tự tạo của model kia chưa có bản ở đây, cộng lượt đang chạy của giọng có
    /// sẵn (để thấy tiến độ sau khi sheet tự sang chip đích).
    private func copyRows(target: VieNeuModelChoice) -> [VieNeuVoiceCopySource] {
        let query = normalizedQuery
        var list = (target == .turbo ? directory.nanoWithoutTurbo : directory.turboWithoutNano)
            .filter { VoiceNameSearch.matches($0.name, normalizedQuery: query) }
        if let running = VieNeuVoiceCopyRunner.shared.job, running.target == target, !list.contains(where: { $0.id == running.id }) {
            list.insert(running, at: 0)
        }
        return list
    }

    private func copyRowViews(_ sources: [VieNeuVoiceCopySource]) -> some View {
        ForEach(sources) { source in
            VieNeuVoiceCopyRow(source: source, entries: downloads.entries) { startCopy(source) }
        }
    }

    private func rows(_ entries: [VieNeuVoiceEntry], reader: VieNeuVoiceSelection?) -> some View {
        ForEach(entries) { entry in
            row(entry, isSelected: entry.selection == reader)
        }
    }

    @ViewBuilder
    private func row(_ entry: VieNeuVoiceEntry, isSelected: Bool) -> some View {
        let isReady = directory.isReady(entry)
        let accelerator = VieNeuCoreMLAccelerator.shared
        // Nano: tải giọng = gói Nano + gói Tăng tốc Core ML (luôn bật, 1.3.919) ⇒ "cần tải" cộng cả gói Core ML còn thiếu.
        let coreMLMissing = entry.model == .nano && !accelerator.isPackageComplete ? VieNeuCoreMLPackage.downloadSizeEstimate : 0
        let download = downloads.entry(id: directory.downloadTarget(for: entry))
        // Nút 🗑: chỉ giọng Turbo tải về đã có file, không lúc đang tải (giọng Nano chung gói, giọng nhân bản nhấn giữ).
        let canDeleteVoice = directory.isTurboVoiceDownloaded(entry) && !(download?.state.isRunning ?? false)
        let listRow = VieNeuVoiceListRow(
            entry: entry,
            isSelected: isSelected,
            isReady: isReady,
            missingBytes: directory.missingBytes(for: entry) + coreMLMissing,
            download: download,
            isPreviewing: preview.isActive(entry.id),
            coreMLStage: entry.model == .nano && isReady ? accelerator.stageText.map { ($0, accelerator.stageFraction) } : nil,
            onPrimary: { primaryTapped(entry) },
            onSelect: { select(entry) },
            onDelete: canDeleteVoice ? { pendingTurboVoiceDeletion = entry } : nil
        )
        listRow.modifier(VieNeuVoiceRowMenu(
            entry: entry,
            copySource: directory.copySource(for: entry),
            canCopy: isReady && !VieNeuVoiceCopyRunner.shared.isRunning,
            onCopy: { startCopy($0) },
            onRename: {
                renameText = entry.name
                renaming = entry
            },
            onDelete: { pendingDeletion = entry }
        ))
    }

    // MARK: - Hành động

    /// Nút tròn: đang tải ⇒ huỷ; đang thử ⇒ dừng; thiếu dữ liệu ⇒ tải; còn lại ⇒ thử giọng.
    private func primaryTapped(_ entry: VieNeuVoiceEntry) {
        let target = directory.downloadTarget(for: entry)
        if downloads.isRunning(id: target) {
            downloads.cancel(id: target)
            return
        }
        if preview.isActive(entry.id) {
            preview.stop()
            return
        }
        guard directory.isReady(entry) else {
            guard entry.model == .nano || directory.isTurboRuntimeAvailable else {
                ToastManager.shared.show(message: "Bản build này chưa có audio.cpp nên chưa dùng được giọng Turbo.", type: .info)
                return
            }
            directory.startDownload(for: entry)
            return
        }
        if preview.play(entry.selection) == .blockedByReader {
            ToastManager.shared.show(message: "Đang phát truyện. Dừng phát rồi thử giọng.", type: .info)
        }
    }

    /// Có mẫu gốc ⇒ tạo luôn; không có ⇒ hỏi trước (tạo từ tiếng máy đọc).
    private func startCopy(_ source: VieNeuVoiceCopySource) {
        if source.hasSample {
            launchCopy(source)
        } else {
            pendingSpokenCopy = source
        }
    }

    /// Bắt đầu lượt; không chạy được ⇒ toast lý do. Chạy được ⇒ sang chip đích để thấy tiến độ.
    private func launchCopy(_ source: VieNeuVoiceCopySource) {
        preview.stop()
        if let reason = VieNeuVoiceCopyRunner.shared.run(source) {
            ToastManager.shared.show(message: reason, type: .info)
            return
        }
        model = source.target
    }

    private func select(_ entry: VieNeuVoiceEntry) {
        guard directory.isReady(entry) else { return }
        ttsManager.selectVieNeuVoice(entry.selection)
    }

    /// Nút 🗑 của giọng Turbo tải về: dừng câu thử của giọng đó (dùng chung runtime Turbo) rồi xoá file của riêng giọng.
    private func commitTurboVoiceDeletion() {
        guard let entry = pendingTurboVoiceDeletion else { return }
        pendingTurboVoiceDeletion = nil
        if preview.isActive(entry.id) { preview.stop() }
        Task {
            do {
                try await VieNeuModelDataRemover.deleteTurboVoice(voiceId: entry.selection.voiceId)
                ToastManager.shared.show(message: "Đã xoá giọng \(entry.name).", type: .success)
            } catch {
                ToastManager.shared.show(message: "Xoá giọng thất bại: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func commitRename() {
        guard let entry = renaming else { return }
        renaming = nil
        do {
            try VieNeuCustomVoiceActions.rename(entry, to: renameText)
        } catch {
            ToastManager.shared.show(message: "Đổi tên thất bại: \(error.localizedDescription)", type: .error)
        }
    }

    private func commitDeletion() {
        guard let entry = pendingDeletion else { return }
        pendingDeletion = nil
        if preview.isActive(entry.id) { preview.stop() }
        do {
            try VieNeuCustomVoiceActions.delete(entry)
        } catch {
            ToastManager.shared.show(message: "Xoá giọng thất bại: \(error.localizedDescription)", type: .error)
        }
    }
}

extension View {
    /// Trình bày sheet chọn giọng VieNeu (kính, vuốt xuống đóng) — Cài đặt TTS gắn ở gốc `Form`.
    func vieNeuVoicePickerSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            Group {
                VieNeuVoicePickerSheet()
                    .presentationDragIndicator(.visible)
            }
            .appGlassSheet()
        }
    }
}
