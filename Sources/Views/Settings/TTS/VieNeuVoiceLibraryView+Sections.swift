import Combine
import SwiftUI

/// Các khối `Form` của `VieNeuVoiceLibraryView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là extension **cùng file type** nên
/// `@State` của view vẫn dùng được; các thành viên dùng chéo file buộc phải để ở mức `internal` (Swift
/// giới hạn `private` theo file) — cùng khuôn `VieNeuTTSTestView+Sections`.
extension VieNeuVoiceLibraryView {
    /// Hộp nhận **bước** của lượt nhân bản từ luồng nền.
    ///
    /// Phải là một class riêng chứ không ghi thẳng `@State`: closure tiến trình truyền xuống
    /// `VieNeuVoiceCloner` là `@Sendable` (nó chạy trong `Task.detached`), nên nó **không được** capture
    /// `self` của View — bẫy đã ghi rõ ở `DictionaryMergeTask.swift:130`. Ở đây closure chỉ capture hộp
    /// này, và hộp tự đẩy mọi cập nhật về `MainActor` trước khi ghi.
    ///
    /// `@unchecked Sendable` vì `stage` **chỉ** được ghi sau khi đã nhảy về `MainActor`.
    final class EnrollProgress: ObservableObject, @unchecked Sendable {
        @Published var stage: VieNeuVoiceCloner.Stage?
    }

    /// Chữ hiện khi đang tạo giọng: **bước cụ thể** nếu đã có, không thì câu chờ chung.
    var workingText: String {
        Self.stageLabel(enrollProgress.stage) ?? workingMessage
    }

    /// Nhãn tiếng Việt cho từng bước. Đặt ở tầng View, **không** đặt ở Service — xem `VieNeuVoiceCloner.Stage`.
    static func stageLabel(_ stage: VieNeuVoiceCloner.Stage?) -> String? {
        switch stage {
        case .some(.decoding): return "Đang đọc file audio mẫu…"
        case .some(.features): return "Đang trích fbank 80-mel…"
        case .some(.loadingGraphs): return "Đang nạp 3 graph nhân bản (~91 MB)…"
        case .some(.speaker): return "Đang tạo x-vector (192 số)…"
        case .some(.codec): return "Đang mã hoá latent 24 kHz…"
        case .some(.style): return "Đang tạo style (50×256)…"
        case .none: return nil
        }
    }
    /// Dung lượng gói graph **khi tải đủ** — hằng số vì lúc chưa tải thì không đo được gì, mà nhãn nút
    /// vẫn phải nói trước sẽ tốn bao nhiêu.
    static var clonePackageBytes: Int64 { VieNeuModelStore.cloneApproximateBytes }

    var missingCloneGraphCount: Int {
        service?.modelStore.missingCloneGraphNames.count ?? VieNeuModelStore.cloneGraphNames.count
    }

    @ViewBuilder
    var clonePackageSection: some View {
        Section {
            if !isModelReady {
                Text("Chưa tải model VieNeu. Mở “Cài đặt VieNeu TTS” để tải model trước.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if hasCloneGraphs {
                LabeledContent("Trạng thái", value: "Đã tải đủ 3 graph")
                Button(role: .destructive) {
                    deleteCloneGraphs()
                } label: {
                    Label("Xoá gói graph nhân bản", systemImage: "trash")
                }
                .disabled(isWorking)
            } else {
                LabeledContent("Còn thiếu", value: "\(missingCloneGraphCount) file")
                if let entry = downloads.entry(id: ModelDownloadCenter.Target.vieNeuClone),
                   entry.state.isRunning {
                    ProgressView(value: entry.fraction) {
                        Text(entry.message).font(.caption)
                    }
                } else {
                    Button {
                        downloadCloneGraphs()
                    } label: {
                        Label(
                            "Tải gói graph nhân bản (\(formattedBytes(Self.clonePackageBytes)))",
                            systemImage: "arrow.down.circle"
                        )
                    }
                }
            }
        } header: {
            SectionHelpHeader("Gói graph nhân bản (tuỳ chọn)", paragraphs: ["Gồm `speaker_encoder` + `codec_encoder` + `reference_encoder`, chỉ cần khi **tạo** giọng mới. Không tải thì 11 giọng sẵn có vẫn dùng bình thường, và engine vẫn nạp được."])
        }
    }

    @ViewBuilder
    var voiceListSection: some View {
        Section {
            if records.isEmpty {
                Text("Chưa có giọng nào. Bấm “Tạo giọng mới” để thu âm hoặc chọn một file audio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    voiceRow(record)
                }
            }
        } header: {
            SectionHelpHeader("Giọng đã tạo (\(records.count))", paragraphs: ["Giọng đã tạo nằm **đầu** danh sách chọn giọng ở Cài đặt. Tên giọng phải khác các giọng đang có."])
        }
    }

    @ViewBuilder
    func voiceRow(_ record: VieNeuCustomVoiceStore.Record) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                Text(subtitle(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // `.borderless` là bắt buộc: trong một hàng của `Form`, mặc định cả hàng là **một** nút nên
            // mọi cú chạm đều rơi vào nút đầu tiên.
            Button {
                // Dừng bản nghe thử của chính mình luôn được phép — kể cả khi TTS đang phát.
                if playingVoiceID == record.id {
                    stopPlayback()
                } else if let reason = playbackBlockReason(action: "nghe thử") {
                    ToastManager.shared.show(message: reason, type: .info)
                } else {
                    playPreview(record)
                }
            } label: {
                Image(systemName: playingVoiceID == record.id ? "stop.circle.fill" : "play.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)
            .accessibilityLabel("Nghe thử \(record.name)")

            // Ngăn kéo `voiceMenuItems` gắn ở `Form` của màn (`VieNeuVoiceLibraryView`), không gắn từng hàng.
            Button {
                menuRecord = record
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Tuỳ chọn cho \(record.name)")
        }
    }

    @ViewBuilder
    func voiceMenuItems(_ record: VieNeuCustomVoiceStore.Record) -> some View {
        SideDrawerActionRow("Tạo lại embedding", systemImage: "arrow.triangle.2.circlepath") { reEnroll(record) }
            .disabled(!hasCloneGraphs || isWorking)
        SideDrawerActionRow("Nghe audio mẫu gốc", systemImage: "waveform") { playSample(record) }
        SideDrawerActionRow("Đổi tên", systemImage: "pencil") {
            renamingID = record.id
            renameText = record.name
        }
        SideDrawerActionRow("Xoá", systemImage: "trash", role: .destructive) { pendingDeletion = record }
    }

    @ViewBuilder
    var creationSection: some View {
        Section {
            if isWorking {
                ProgressView {
                    Text(workingText).font(.caption)
                }
            } else {
                Button {
                    if let reason = playbackBlockReason() {
                        ToastManager.shared.show(message: reason, type: .info)
                        return
                    }
                    showingCreator = true
                } label: {
                    Label("Tạo giọng mới", systemImage: "plus.circle")
                }
                .disabled(!isModelReady || !hasCloneGraphs)
            }
        } header: {
            // Đoạn cuối trước đây là section rỗng chỉ có footer ở `VieNeuVoiceLibraryView`, gộp vào đây.
            SectionHelpHeader("Tạo giọng", paragraphs: [
                "Thu âm 3–8 giây, hoặc chọn một file audio có sẵn. Audio mẫu được giữ lại để nghe đối chiếu và để tạo lại embedding mà không phải thu lại.",
                "Bản Nano cho chất lượng nhân bản thấp hơn bản Turbo. Thu âm ở nơi yên tĩnh, 3–8 giây, một người nói — audio mẫu càng sạch thì giọng nhân bản càng giống."
            ])
        } footer: {
            // Lý do nút "Tạo giọng mới" bị khoá (trạng thái) giữ ở footer; phần giải thích nằm ở nút "?".
            if !isModelReady {
                Text("Cần tải model VieNeu trước.")
            } else if !hasCloneGraphs {
                Text("Cần tải gói graph nhân bản ở trên trước.")
            }
        }
    }

    func subtitle(for record: VieNeuCustomVoiceStore.Record) -> String {
        let created = record.createdAt.formatted(date: .abbreviated, time: .shortened)
        let sample = store?.sampleURL(for: record) != nil ? "có audio mẫu" : "thiếu audio mẫu"
        return "\(created) · \(sample)"
    }

    func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
