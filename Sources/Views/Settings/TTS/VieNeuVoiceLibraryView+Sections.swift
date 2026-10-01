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
                if isDownloading {
                    ProgressView(value: downloadProgress) {
                        Text(downloadMessage).font(.caption)
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
            Text("Gói graph nhân bản (tuỳ chọn)")
        } footer: {
            Text("Gồm `speaker_encoder` + `codec_encoder` + `reference_encoder`, chỉ cần khi **tạo** giọng mới. Không tải thì 11 giọng sẵn có vẫn dùng bình thường, và engine vẫn nạp được.")
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
            Text("Giọng đã tạo (\(records.count))")
        } footer: {
            Text("Giọng đã tạo nằm **đầu** danh sách chọn giọng ở Cài đặt. Tên giọng phải khác các giọng đang có.")
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

            Menu {
                Button {
                    reEnroll(record)
                } label: {
                    Label("Tạo lại embedding", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!hasCloneGraphs || isWorking)

                Button {
                    playSample(record)
                } label: {
                    Label("Nghe audio mẫu gốc", systemImage: "waveform")
                }

                Button {
                    renamingID = record.id
                    renameText = record.name
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    pendingDeletion = record
                } label: {
                    Label("Xoá", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Tuỳ chọn cho \(record.name)")
        }
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
        } footer: {
            if !isModelReady {
                Text("Cần tải model VieNeu trước.")
            } else if !hasCloneGraphs {
                Text("Cần tải gói graph nhân bản ở trên trước.")
            } else {
                Text("Thu âm 3–8 giây, hoặc chọn một file audio có sẵn. Audio mẫu được giữ lại để nghe đối chiếu và để tạo lại embedding mà không phải thu lại.")
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
