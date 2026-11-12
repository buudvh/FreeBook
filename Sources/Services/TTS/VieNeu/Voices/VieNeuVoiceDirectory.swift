import AVFoundation
import Foundation
import Observation

/// Nguồn sự thật **danh sách giọng VieNeu + trạng thái tải** cho sheet chọn giọng và hàng "Giọng đọc" ở Cài đặt TTS
/// (1.3.900). View đọc các mảng trong `body`; mọi việc đọc đĩa chạy ngoài main (`reload()`), main chỉ gán kết quả.
///
/// - Nano: 11 giọng có sẵn (`voices_v3_nano.json` khi đã tải, không thì `VieNeuBuiltinVoiceList`) + giọng nhân bản
///   (`VieNeuCustomVoiceStore`). Mọi giọng Nano dùng chung một gói model ⇒ một trạng thái tải.
/// - Turbo: 25 giọng manifest (file trên máy, không thì danh sách dựng sẵn) chia "Tuyển chọn" / "Giọng khác" + giọng tự
///   tạo (`VieNeuTurboCustomVoiceRepository`). Mỗi giọng manifest một cặp file vài KB; model + `sea_g2p.bin` dùng chung.
/// - `nanoWithoutTurbo`: giọng Nano tự tạo chưa có bản Turbo (khớp qua `Record.sourceNanoVoiceId`).
@MainActor
@Observable
final class VieNeuVoiceDirectory {
    static let shared = VieNeuVoiceDirectory()

    /// Giọng Nano tự tạo chưa có bản Turbo — hàng "Tạo bản Turbo" trong chip Turbo.
    struct NanoOnlyVoice: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let sampleSeconds: Double?
        /// Còn mẫu âm thanh gốc (bắt buộc để tạo bản Turbo).
        let hasSample: Bool
    }

    /// Ảnh chụp dựng ngoài main.
    struct Snapshot: Sendable {
        var nanoPresets: [VieNeuVoiceEntry] = []
        var nanoMine: [VieNeuVoiceEntry] = []
        var turboFeatured: [VieNeuVoiceEntry] = []
        var turboOthers: [VieNeuVoiceEntry] = []
        var turboMine: [VieNeuVoiceEntry] = []
        var nanoWithoutTurbo: [NanoOnlyVoice] = []
        var isNanoReady = false
        var nanoMissingBytes: Int64 = 0
        var isTurboBaseReady = false
        var turboBaseMissingBytes: Int64 = 0
        var downloadedTurboVoiceIds: Set<String> = []
    }

    private(set) var snapshot: Snapshot
    private(set) var hasLoaded = false
    /// Bản build có audio.cpp — không có thì Turbo không chạy được dù đủ file.
    let isTurboRuntimeAvailable = VieNeuTurboRuntime.isAvailable
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingReload = false

    private init() {
        // Danh sách dựng sẵn ngay từ đầu để lần vẽ đầu tiên đã có hàng; `reload()` thay bằng dữ liệu thật.
        snapshot = Self.buildSnapshot(turboRecords: [], readsDisk: false)
    }

    // MARK: - Truy vấn cho View

    var nanoPresets: [VieNeuVoiceEntry] { snapshot.nanoPresets }
    var nanoMine: [VieNeuVoiceEntry] { snapshot.nanoMine }
    var turboFeatured: [VieNeuVoiceEntry] { snapshot.turboFeatured }
    var turboOthers: [VieNeuVoiceEntry] { snapshot.turboOthers }
    var turboMine: [VieNeuVoiceEntry] { snapshot.turboMine }
    var nanoWithoutTurbo: [NanoOnlyVoice] { snapshot.nanoWithoutTurbo }
    var isNanoReady: Bool { snapshot.isNanoReady }
    var isTurboBaseReady: Bool { snapshot.isTurboBaseReady }
    var turboBaseMissingBytes: Int64 { snapshot.turboBaseMissingBytes }

    func entry(for selection: VieNeuVoiceSelection) -> VieNeuVoiceEntry? {
        let all = snapshot.nanoMine + snapshot.nanoPresets + snapshot.turboMine + snapshot.turboFeatured + snapshot.turboOthers
        return all.first { $0.selection == selection }
    }

    /// Đủ dữ liệu để đọc bằng giọng này.
    func isReady(_ entry: VieNeuVoiceEntry) -> Bool {
        switch entry.model {
        case .nano: return snapshot.isNanoReady
        case .turbo:
            return snapshot.isTurboBaseReady
                && (entry.isMine || snapshot.downloadedTurboVoiceIds.contains(entry.selection.voiceId))
        }
    }

    /// Byte còn phải tải cho giọng này (file giọng Turbo vài KB không tính).
    func missingBytes(for entry: VieNeuVoiceEntry) -> Int64 {
        entry.model == .nano ? snapshot.nanoMissingBytes : snapshot.turboBaseMissingBytes
    }

    /// Đích `ModelDownloadCenter` của giọng: mọi giọng Nano chung một đích, mỗi giọng Turbo một đích.
    func downloadTarget(for entry: VieNeuVoiceEntry) -> String {
        entry.model == .nano
            ? ModelDownloadCenter.Target.vieNeuModel
            : ModelDownloadCenter.Target.vieNeuTurboVoice(entry.selection.voiceId)
    }

    /// Bắt đầu tải dữ liệu còn thiếu của giọng (Nano: cả gói model; Turbo: model nếu thiếu + file của giọng).
    func startDownload(for entry: VieNeuVoiceEntry) {
        let center = ModelDownloadCenter.shared
        switch entry.model {
        case .nano: center.startVieNeuModel()
        case .turbo: center.startVieNeuTurbo(voiceId: entry.selection.voiceId, title: "Giọng \(entry.name)")
        }
    }

    // MARK: - Nạp

    /// Đọc lại danh sách + trạng thái file (ngoài main). Gọi dồn dập thì gộp: lượt đang chạy xong sẽ chạy thêm một lượt.
    func reload() {
        guard reloadTask == nil else {
            pendingReload = true
            return
        }
        VieNeuTurboCustomVoiceRepository.shared.reload()
        let turboRecords = VieNeuTurboCustomVoiceRepository.shared.voices
        reloadTask = Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) {
                Self.buildSnapshot(turboRecords: turboRecords, readsDisk: true)
            }.value
            guard let self else { return }
            snapshot = built
            hasLoaded = true
            reloadTask = nil
            if pendingReload {
                pendingReload = false
                reload()
            }
        }
    }

    /// Sau một lượt tải / tạo giọng: file trên máy đổi ⇒ đọc lại.
    func refreshAvailability() {
        reload()
    }

    // MARK: - Dựng ảnh chụp (ngoài main)

    private nonisolated static func buildSnapshot(
        turboRecords: [VieNeuTurboCustomVoiceStore.Record],
        readsDisk: Bool
    ) -> Snapshot {
        var result = Snapshot()
        let nanoStore = readsDisk ? (try? VieNeuModelStore()) : nil
        let turboStore = readsDisk ? (try? VieNeuTurboModelStore()) : nil
        fillNano(into: &result, store: nanoStore)
        fillTurbo(into: &result, store: turboStore, nanoStore: nanoStore, records: turboRecords)

        let linked = Set(turboRecords.compactMap(\.sourceNanoVoiceId))
        if let nanoStore {
            let customStore = VieNeuCustomVoiceStore(rootURL: nanoStore.rootURL)
            result.nanoWithoutTurbo = customStore.loadLeniently()
                .filter { !linked.contains($0.id) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { record in
                    let sample = customStore.sampleURL(for: record)
                    return NanoOnlyVoice(
                        id: record.id,
                        name: record.name,
                        sampleSeconds: sample.flatMap(audioSeconds),
                        hasSample: sample != nil
                    )
                }
        }
        return result
    }

    private nonisolated static func fillNano(into result: inout Snapshot, store: VieNeuModelStore?) {
        result.isNanoReady = store?.isReady ?? false
        result.nanoMissingBytes = store?.missingBytes(of: VieNeuModelStore.requiredNames)
            ?? VieNeuModelStore.requiredNames.reduce(Int64(0)) { $0 + (VieNeuModelStore.fileByteCounts[$1] ?? 0) }

        var presets: [(name: String, description: String)] = VieNeuBuiltinVoiceList.nano.map { ($0.name, $0.description) }
        var defaultName = VieNeuBuiltinVoiceList.nanoDefaultName
        if let store, store.exists("voices_v3_nano.json"), let catalog = try? VieNeuVoiceCatalog.load(modelStore: store) {
            presets = catalog.presets.filter { !$0.isCloned }.map { ($0.voice.name, $0.summary) }
            defaultName = catalog.defaultVoiceName
        }
        presets.sort { lhs, rhs in
            if lhs.name == defaultName { return true }
            if rhs.name == defaultName { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        result.nanoPresets = presets.map { preset in
            VieNeuVoiceEntry(
                selection: VieNeuVoiceSelection(model: .nano, voiceId: preset.name),
                name: preset.name,
                detail: VieNeuVoiceEntry.shortTraits(preset.description),
                weight: .light,
                group: .nanoPreset,
                nanoRecordId: nil
            )
        }

        guard let store else { return }
        let customStore = VieNeuCustomVoiceStore(rootURL: store.rootURL)
        result.nanoMine = customStore.loadLeniently()
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { record in
                VieNeuVoiceEntry(
                    selection: VieNeuVoiceSelection(model: .nano, voiceId: record.name),
                    name: record.name,
                    detail: VieNeuVoiceEntry.sampleDetail(seconds: customStore.sampleURL(for: record).flatMap(audioSeconds))
                        ?? VieNeuVoiceCatalog.customSummary,
                    weight: .light,
                    group: .mine,
                    nanoRecordId: record.id
                )
            }
    }

    private nonisolated static func fillTurbo(
        into result: inout Snapshot,
        store: VieNeuTurboModelStore?,
        nanoStore: VieNeuModelStore?,
        records: [VieNeuTurboCustomVoiceStore.Record]
    ) {
        let g2pBytes = VieNeuModelStore.fileByteCounts["sea_g2p.bin"] ?? 0
        let hasG2P = nanoStore?.exists("sea_g2p.bin") ?? false
        let hasModel = store?.hasModel ?? false
        let hasManifest = store?.hasManifest ?? false
        result.isTurboBaseReady = VieNeuTurboRuntime.isAvailable && hasModel && hasManifest && hasG2P
        result.turboBaseMissingBytes = (hasModel ? 0 : VieNeuTurboModelStore.modelByteCount) + (hasG2P ? 0 : g2pBytes)

        var voices = VieNeuBuiltinVoiceList.turbo
        if let store, hasManifest, let manifest = try? VieNeuTurboVoiceManifest.load(from: store.manifestURL),
           !manifest.voices.isEmpty {
            voices = manifest.voices
        }
        if let store {
            result.downloadedTurboVoiceIds = Set(voices.map(\.id).filter { store.hasVoice(voiceId: $0) })
        }
        let entries = voices.map { voice in
            VieNeuVoiceEntry(
                selection: VieNeuVoiceSelection(model: .turbo, voiceId: voice.id),
                name: voice.name,
                detail: voice.traitsSummary,
                weight: .turbo(frames: voice.frames),
                group: voice.isFeatured ? .turboFeatured : .turboOther,
                nanoRecordId: nil
            )
        }
        result.turboFeatured = entries.filter { $0.group == .turboFeatured }
        result.turboOthers = entries.filter { $0.group == .turboOther }
        result.turboMine = records
            .filter { store?.hasVoice(voiceId: $0.id) ?? true }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { record in
                VieNeuVoiceEntry(
                    selection: VieNeuVoiceSelection(model: .turbo, voiceId: record.id),
                    name: record.name,
                    detail: VieNeuVoiceEntry.sampleDetail(seconds: record.sampleSeconds),
                    weight: .turbo(frames: record.frames),
                    group: .mine,
                    nanoRecordId: nil
                )
            }
    }

    /// Độ dài file âm thanh (chỉ đọc header).
    private nonisolated static func audioSeconds(_ url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
