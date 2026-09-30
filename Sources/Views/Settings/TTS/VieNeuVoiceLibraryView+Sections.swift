import SwiftUI

/// Các khối `Form` của `VieNeuVoiceLibraryView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là extension **cùng file type** nên
/// `@State` của view vẫn dùng được; các thành viên dùng chéo file buộc phải để ở mức `internal` (Swift
/// giới hạn `private` theo file) — cùng khuôn `VieNeuTTSTestView+Sections`.
extension VieNeuVoiceLibraryView {
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
                if playingVoiceID == record.id {
                    stopPlayback()
                } else {
                    playPreview(record)
                }
            } label: {
                Image(systemName: playingVoiceID == record.id ? "stop.circle.fill" : "play.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(isWorking || isBlockedByPlayback)
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
                    Text(workingMessage).font(.caption)
                }
            } else {
                Button {
                    showingCreator = true
                } label: {
                    Label("Tạo giọng mới", systemImage: "plus.circle")
                }
                .disabled(!isModelReady || !hasCloneGraphs || isBlockedByPlayback)
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
