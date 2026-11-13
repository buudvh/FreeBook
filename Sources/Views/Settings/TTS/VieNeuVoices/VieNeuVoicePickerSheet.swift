import SwiftUI

/// **Sheet chọn giọng VieNeu** (1.3.900, mockup anh Bửu duyệt): chip "Nano | Turbo" (mở ra chọn sẵn model đang dùng),
/// rồi "Giọng của tôi" (giọng nhân bản của model đó), rồi Turbo "Tuyển chọn" + "Giọng khác" / Nano "Giọng có sẵn".
///
/// - Không có dòng tải model riêng: mỗi giọng có nút ⬇ của nó. Nano tải chung một gói ⇒ bấm ⬇ một giọng Nano thì **mọi**
///   hàng Nano cùng hiện tiến độ; Turbo tải model nếu thiếu rồi file của đúng giọng đó ⇒ tiến độ chỉ ở hàng đó.
/// - Chọn giọng = `TTSManager.selectVieNeuVoice` ⇒ model đi theo giọng (khác model thì trình đọc nạp lại engine).
/// - Thử giọng qua `VieNeuVoicePreviewPlayer`; sheet đóng thì dừng câu thử.
/// - Nhấn giữ giọng nhân bản ⇒ Đổi tên / Xoá (thay màn "Giọng của tôi" cũ). Nhấn giữ giọng có sẵn đã tải ⇒ "Xoá dữ liệu
///   Nano / Turbo" (`VieNeuModelDataRemover`, 1.3.919 — lối duy nhất lấy lại dung lượng model).
/// - Ô tìm theo tên giọng (`VoiceNameSearch`: bỏ dấu, "đ" = "d") lọc trong chip đang chọn; đang tìm thì ẩn hàng
///   "Nhân bản giọng đọc", nhóm không còn giọng nào khớp thì ẩn cả nhóm.
/// - Hàng đầu "Nhân bản giọng đọc" ⇒ `VieNeuVoiceCloneSheet` (1.3.901); giọng Nano tự tạo chưa có bản Turbo hiện trong
///   "Giọng của tôi" của chip Turbo với nút "Tạo bản Turbo" (`VieNeuTurboCopyRow`).
struct VieNeuVoicePickerSheet: View {
    static let helpText: [LocalizedStringKey] = [
        "Nhẹ: Nano, khoảng 29 CPU-giây mỗi 1.000 ký tự. Vừa: Turbo, 37–43 (đo Minh Quân Pro, Mai Anh). Nặng: Turbo có mẫu dài, ước tính. Đo trên iPhone 11."
    ]

    @ObservedObject private var downloads = ModelDownloadCenter.shared
    @ObservedObject private var ttsManager = TTSManager.shared
    @State private var model: VieNeuModelChoice = VieNeuModelChoice.current
    @State private var renaming: VieNeuVoiceEntry?
    @State private var renameText = ""
    @State private var pendingDeletion: VieNeuVoiceEntry?
    @State private var pendingDataRemoval: VieNeuModelChoice?
    @State private var isClonePresented = false
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
        .onChange(of: VieNeuTurboCopyRunner.shared.resultToken) { _, _ in
            let runner = VieNeuTurboCopyRunner.shared
            ToastManager.shared.show(message: runner.resultMessage, type: runner.resultIsError ? .error : .success)
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
            pendingDataRemoval == .turbo ? "Xoá dữ liệu Turbo?" : "Xoá dữ liệu Nano?",
            isPresented: Binding(get: { pendingDataRemoval != nil }, set: { if !$0 { pendingDataRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá dữ liệu", role: .destructive) { commitDataRemoval() }
            Button("Huỷ", role: .cancel) { pendingDataRemoval = nil }
        } message: {
            Text(pendingDataRemoval == .turbo
                 ? "Xoá model Turbo và các giọng Turbo đã tải. Giọng nhân bản giữ nguyên; tải lại bằng nút ⬇ của giọng."
                 : "Xoá model Nano và gói Tăng tốc Core ML. Giọng nhân bản giữ nguyên; tải lại bằng nút ⬇ của giọng.")
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
        let presets = filtered(directory.nanoPresets)
        if !mine.isEmpty {
            Section("Giọng của tôi") { rows(mine, reader: reader) }
        }
        if !presets.isEmpty {
            Section("Giọng có sẵn") { rows(presets, reader: reader) }
        }
        if mine.isEmpty, presets.isEmpty, !normalizedQuery.isEmpty {
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
        let copies = directory.nanoWithoutTurbo.filter { VoiceNameSearch.matches($0.name, normalizedQuery: query) }
        let featured = filtered(directory.turboFeatured)
        let others = filtered(directory.turboOthers)
        if !mine.isEmpty || !copies.isEmpty {
            Section("Giọng của tôi") {
                rows(mine, reader: reader)
                ForEach(copies) { voice in
                    VieNeuTurboCopyRow(voice: voice, entries: downloads.entries)
                }
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
        let listRow = VieNeuVoiceListRow(
            entry: entry,
            isSelected: isSelected,
            isReady: isReady,
            missingBytes: directory.missingBytes(for: entry) + coreMLMissing,
            download: downloads.entry(id: directory.downloadTarget(for: entry)),
            isPreviewing: preview.isActive(entry.id),
            coreMLStage: entry.model == .nano && isReady ? accelerator.stageText.map { ($0, accelerator.stageFraction) } : nil,
            onPrimary: { primaryTapped(entry) },
            onSelect: { select(entry) }
        )
        if entry.isMine {
            listRow.contextMenu {
                Button {
                    renameText = entry.name
                    renaming = entry
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    pendingDeletion = entry
                } label: {
                    Label("Xoá giọng", systemImage: "trash")
                }
            }
        } else if isReady {
            listRow.contextMenu {
                Button(role: .destructive) {
                    pendingDataRemoval = entry.model
                } label: {
                    Label(entry.model == .turbo ? "Xoá dữ liệu Turbo" : "Xoá dữ liệu Nano", systemImage: "trash")
                }
            }
        } else {
            listRow
        }
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

    private func select(_ entry: VieNeuVoiceEntry) {
        guard directory.isReady(entry) else { return }
        ttsManager.selectVieNeuVoice(entry.selection)
    }

    private func commitDataRemoval() {
        guard let model = pendingDataRemoval else { return }
        pendingDataRemoval = nil
        preview.stop()
        Task {
            do {
                if model == .turbo {
                    try await VieNeuModelDataRemover.deleteTurbo()
                } else {
                    try await VieNeuModelDataRemover.deleteNano()
                }
                directory.reload()
                ToastManager.shared.show(message: "Đã xoá dữ liệu \(model.label).", type: .success)
            } catch {
                ToastManager.shared.show(message: "Xoá dữ liệu thất bại: \(error.localizedDescription)", type: .error)
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
