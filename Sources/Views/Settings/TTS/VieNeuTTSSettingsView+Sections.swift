import SwiftUI

/// Các khối thông tin của `VieNeuTTSSettingsView` (Nano, Tăng tốc Core ML, Turbo, giọng nhân bản) + hàng "Xoá tất cả dữ
/// liệu Nano / Turbo" + số liệu đọc đĩa.
/// Tách khỏi file chính vì trần 400 dòng; thành viên dùng chéo file để `internal`.
extension VieNeuTTSSettingsView {
    /// Số liệu đọc từ đĩa của trang — dựng ngoài main (`loadDiskSnapshot`), không đọc trong `body`.
    struct DiskSnapshot: Sendable {
        var nanoMissingCount = VieNeuModelStore.requiredNames.count
        var nanoBytes: Int64 = 0
        var hasNanoClonePack = false
        var nanoClonePackBytes: Int64 = 0
        var hasTurboModel = false
        var turboVoiceCount = 0
        var turboVoiceBytes: Int64 = 0
        var hasTurboClonePack = false
        var turboClonePackBytes: Int64 = 0
        var nanoCustomCount = 0
        var nanoCustomBytes: Int64 = 0
        var turboCustomCount = 0
        var turboCustomBytes: Int64 = 0
        /// Byte "Xoá tất cả dữ liệu Nano" lấy lại ở thư mục Nano (`VieNeuModelStore.removableBytes`, chưa cộng Core ML).
        var nanoRemovableBytes: Int64 = 0
        /// Byte "Xoá tất cả dữ liệu Turbo" lấy lại: cả `Models/` + `Voices/` của Turbo (model, manifest, giọng tải về).
        var turboRemovableBytes: Int64 = 0
    }

    // MARK: - Nano

    var nanoSection: some View {
        Section {
            LabeledContent("Trạng thái", value: snapshot.map(Self.nanoStatus) ?? "…")
            LabeledContent("Dung lượng", value: snapshot.map { Self.size($0.nanoBytes) } ?? "…")
            LabeledContent("Giọng có sẵn", value: "\(directory.nanoPresets.count) giọng")
            LabeledContent("Gói nhân bản giọng", value: snapshot.map {
                $0.hasNanoClonePack ? "Đã tải · \(Self.size($0.nanoClonePackBytes))" : "Chưa tải"
            } ?? "…")
            if snapshot != nil, nanoWipeBytes > 0 {
                wipeRow(.nano, bytes: nanoWipeBytes)
            }
        } header: {
            SectionHelpHeader("Nano", paragraphs: [
                "VieNeu-TTS v3 **Nano** chạy hoàn toàn trên máy (ONNX Runtime, 24 kHz). Mọi giọng Nano dùng chung **một bộ graph** (8 file), nên tải một giọng là có cả bộ.",
                "Tải ở **sheet chọn giọng** (hàng \"Giọng đọc VieNeu\" phía trên). **Xoá tất cả dữ liệu Nano** xoá cả bộ graph, gói nhân bản Nano và gói Tăng tốc Core ML; giọng nhân bản giữ nguyên."
            ])
        }
    }

    /// Dung lượng "Xoá tất cả dữ liệu Nano" lấy lại: thư mục Nano (đúng danh sách `deleteAll`) + gói và bản biên dịch Core ML.
    var nanoWipeBytes: Int64 {
        (snapshot?.nanoRemovableBytes ?? 0) + accelerator.packageBytes + accelerator.cacheBytes
    }

    /// Hàng "Xoá tất cả dữ liệu Nano / Turbo" (đỏ, dung lượng bên phải; đang xoá ⇒ vòng xoay). Bấm ⇒ hộp xác nhận ở file chính.
    func wipeRow(_ model: VieNeuModelChoice, bytes: Int64) -> some View {
        Button {
            pendingWipe = model
        } label: {
            HStack(spacing: 12) {
                Label("Xoá tất cả dữ liệu \(model.label)", systemImage: "trash")
                Spacer(minLength: 8)
                if wipingModel == model {
                    ProgressView()
                } else {
                    Text(Self.size(bytes))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            // `.red` literal có chủ ý: hành động xoá, không theo màu nhấn.
            .foregroundColor(.red)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(wipingModel != nil)
    }

    nonisolated private static func nanoStatus(_ snapshot: DiskSnapshot) -> String {
        snapshot.nanoMissingCount == 0
            ? "Đã tải đủ \(VieNeuModelStore.requiredNames.count) file"
            : "Còn thiếu \(snapshot.nanoMissingCount) file"
    }

    // MARK: - Tăng tốc Core ML

    var coreMLSection: some View {
        Section {
            LabeledContent("Trạng thái") {
                Text(coreMLStatus.text)
                    .foregroundColor(coreMLStatus.color)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Gói", value: accelerator.packageBytes > 0 ? Self.size(accelerator.packageBytes) : "Chưa tải")
            LabeledContent("Bản biên dịch", value: "\(accelerator.compiledCount) khung · \(Self.size(accelerator.cacheBytes))")
            LabeledContent("Phiên bản gói", value: String(VieNeuCoreMLPackage.revision.prefix(8)))
        } header: {
            SectionHelpHeader("Tăng tốc Core ML", paragraphs: [
                "**Luôn bật.** Tải xong gói Nano là app tự tải thêm gói Core ML (khoảng \(Self.size(VieNeuCoreMLPackage.downloadSizeEstimate))), biên dịch và **tự kiểm chất lượng** một lần; qua kiểm thì trình đọc Nano dùng nó.",
                "Chất lượng y hệt bản thường; trên iPhone 11 nhanh khoảng **gấp đôi** và máy mát hơn. Đoạn quá dài hoặc Core ML gặp lỗi thì đoạn đó tự đọc bằng đường thường (ORT)."
            ])
        }
    }

    /// Thứ tự: đang chạy ⇒ bước hiện tại; đã tự kiểm ⇒ sẵn sàng; chưa có gói Nano ⇒ chờ; lỗi ⇒ đỏ; còn lại ⇒ chưa chuẩn bị.
    private var coreMLStatus: (text: String, color: Color) {
        if accelerator.isBusy, let stage = accelerator.stageText {
            let prefix = "Tăng tốc Core ML · "
            return (stage.hasPrefix(prefix) ? String(stage.dropFirst(prefix.count)) : stage, .accentColor)
        }
        // `.green` / `.red` literal có chủ ý: trạng thái, không theo màu nhấn.
        if accelerator.isVerified { return ("Sẵn sàng · đã tự kiểm", .green) }
        if let snapshot, snapshot.nanoMissingCount > 0 { return ("Chờ gói Nano", .secondary) }
        if let error = accelerator.errorMessage { return ("Lỗi: \(error)", .red) }
        return ("Chưa chuẩn bị", .secondary)
    }

    // MARK: - Turbo

    var turboSection: some View {
        Section {
            if directory.isTurboRuntimeAvailable {
                LabeledContent("Model", value: snapshot.map {
                    $0.hasTurboModel ? "GGUF q8_0 · \(Self.size(VieNeuTurboModelStore.modelByteCount))" : "Chưa tải"
                } ?? "…")
                LabeledContent("Giọng đã tải", value: snapshot.map {
                    "\($0.turboVoiceCount) giọng · \(Self.size($0.turboVoiceBytes))"
                } ?? "…")
                LabeledContent("Gói nhân bản giọng", value: snapshot.map {
                    $0.hasTurboClonePack ? "Đã tải · \(Self.size($0.turboClonePackBytes))" : "Chưa tải"
                } ?? "…")
                LabeledContent("Tăng tốc AMX") {
                    // `.green` literal có chủ ý: trạng thái, không theo màu nhấn (như Tăng tốc Core ML của Nano).
                    if turboAMXDisabledBuild == VieNeuTurboAcceleration.currentBuild {
                        Text("Đã tự tắt tới bản sau").foregroundColor(.secondary)
                    } else {
                        Text("Đang dùng").foregroundColor(.green)
                    }
                }
                // TẠM (1.3.932): màn đo codec AMX vs Neural Engine — gỡ cùng `TurboCodecBenchView` khi có kết luận.
                NavigationLink {
                    TurboCodecBenchView()
                } label: {
                    Label("Đo codec: AMX vs Neural Engine (tạm)", systemImage: "gauge.with.dots.needle.33percent")
                }
            } else {
                Text("Bản build này chưa có audio.cpp")
                    .foregroundColor(.secondary)
            }
            if let snapshot, snapshot.turboRemovableBytes > 0 {
                wipeRow(.turbo, bytes: snapshot.turboRemovableBytes)
            }
        } header: {
            SectionHelpHeader("Turbo", paragraphs: [
                "VieNeu-TTS v3 **Turbo**: model GGUF q8_0 chạy trên máy qua **audio.cpp** (48 kHz). Model và dữ liệu từng giọng tải **theo giọng** ở sheet chọn giọng; xoá một giọng bằng nút 🗑 cuối hàng giọng đó.",
                "**Tăng tốc AMX (luôn bật):** phần giải mã ra tiếng (codec) và bước nạp chữ + giọng mẫu ở đầu mỗi đoạn chạy phép nhân ma trận trên bộ tăng tốc AMX của chip qua Accelerate. Trên iPhone 11 Turbo nhanh hơn khoảng **37%** (codec 3,3×, bước nạp 1,9×); tiếng gần như y hệt — codec chỉ khác sai số làm tròn, bước nạp còn gần bản gốc hơn đường thường. Nếu app dừng giữa lượt đọc đầu tiên có AMX, lần mở sau app **tự tắt AMX tới bản build sau** và log ghi lý do.",
                "**Xoá tất cả dữ liệu Turbo** xoá model và mọi giọng Turbo đã tải; giọng nhân bản giữ nguyên."
            ])
        }
    }

    // MARK: - Giọng nhân bản

    var customVoicesSection: some View {
        Section {
            LabeledContent("Nano", value: snapshot.map {
                "\($0.nanoCustomCount) giọng · \(Self.size($0.nanoCustomBytes))"
            } ?? "…")
            LabeledContent("Turbo", value: snapshot.map {
                "\($0.turboCustomCount) giọng · \(Self.size($0.turboCustomBytes))"
            } ?? "…")
        } header: {
            SectionHelpHeader("Giọng nhân bản", paragraphs: [
                "Giọng tự tạo từ mẫu thu âm / file — tạo ở hàng **\"Nhân bản giọng đọc\"** của sheet chọn giọng; đổi tên / xoá bằng cách nhấn giữ giọng ở đó."
            ])
        }
    }

    // MARK: - Đọc đĩa (ngoài main)

    nonisolated static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    nonisolated static func loadDiskSnapshot() -> DiskSnapshot {
        var result = DiskSnapshot()
        if let nano = try? VieNeuModelStore() {
            result.nanoMissingCount = nano.missingNames.count
            result.nanoBytes = nano.totalBytes
            result.hasNanoClonePack = nano.hasCloneGraphs
            result.nanoClonePackBytes = nano.cloneTotalBytes
            result.hasTurboClonePack = nano.hasTurboCloneGraphs
            result.turboClonePackBytes = nano.turboCloneTotalBytes
            let custom = VieNeuCustomVoiceStore(rootURL: nano.rootURL)
            result.nanoCustomCount = custom.loadLeniently().count
            result.nanoCustomBytes = custom.totalBytes
            result.nanoRemovableBytes = nano.removableBytes
        }
        if let turbo = try? VieNeuTurboModelStore() {
            result.hasTurboModel = turbo.hasModel
            let fileManager = FileManager.default
            let voiceDirectories = (try? fileManager.contentsOfDirectory(
                at: turbo.voicesURL, includingPropertiesForKeys: [.isDirectoryKey]
            )) ?? []
            for directory in voiceDirectories
            where (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                && turbo.hasVoice(voiceId: directory.lastPathComponent) {
                result.turboVoiceCount += 1
                result.turboVoiceBytes += bytes(in: directory)
            }
            result.turboCustomCount = (try? VieNeuTurboCustomVoiceStore(modelStore: turbo).load())?.count ?? 0
            result.turboCustomBytes = bytes(in: turbo.customVoicesURL)
            result.turboRemovableBytes = bytes(in: turbo.modelsURL) + bytes(in: turbo.voicesURL)
        }
        return result
    }

    /// Tổng dung lượng file thường trong một thư mục (đệ quy); không có thư mục ⇒ 0.
    nonisolated private static func bytes(in directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
