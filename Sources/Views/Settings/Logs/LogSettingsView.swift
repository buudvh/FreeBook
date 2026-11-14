import SwiftUI

/// Màn "Ghi log hệ thống" (Cài đặt → Nhà Phát Triển): công tắc log, chẩn đoán fd (`FileDescriptorCensus`,
/// `FileDescriptorSweeper`, 1.3.521) và — từ 1.3.948 (log SQLite theo phiên, anh Bửu chọn ở grill-me) — **danh sách phiên**:
/// mỗi lần mở app một hàng (giờ · bản build · số dòng · số lỗi, badge "Chết đột ngột"), tick chọn ⇒ "Xuất N phiên (.txt)"
/// (bảng chia sẻ) / "Xoá N phiên" / "Xoá tất cả". Không có màn xem từng dòng. Danh sách đọc qua `AppLogger` ở nền.
struct LogSettingsView: View {
    private struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @AppStorage("isLoggingEnabled") private var isLoggingEnabled = false
    @AppStorage("isCompactSuccessLogEnabled") private var isCompactSuccessLogEnabled = true
    @AppStorage("isTTSVerboseLoggingEnabled") private var isTTSVerboseLoggingEnabled = false
    @AppStorage(FileDescriptorSweeper.enabledKey) private var isFDSweeperEnabled = true
    @State private var sessions: [AppLogger.SessionSummary] = []
    @State private var storeBytes: Int64 = 0
    @State private var selected: Set<Int64> = []
    @State private var hasLoaded = false
    @State private var isExporting = false
    @State private var exportFile: ExportFile?
    @State private var openFileCount: Int = 0
    @State private var openFileLimit: Int = 0
    @State private var showingClearLogAlert = false

    var body: some View {
        Form { Group {
            Section(header: Text("Cấu Hình")) {
                Toggle(isOn: $isLoggingEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ghi log hệ thống")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Bật ghi log giúp chẩn đoán và sửa lỗi. Dòng lỗi (❌) luôn được ghi.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: isLoggingEnabled) { _, newValue in
                    AppLogger.shared.isLoggingEnabled = newValue
                }

                if isLoggingEnabled {
                    Toggle(isOn: $isCompactSuccessLogEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Thu gọn log kết quả Extension")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Rút gọn dữ liệu trả về của extension trong log để tiết kiệm dung lượng đĩa.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                    .onChange(of: isCompactSuccessLogEnabled) { _, newValue in
                        AppLogger.shared.isCompactSuccessLogEnabled = newValue
                    }

                    Toggle(isOn: $isTTSVerboseLoggingEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ghi log TTS chi tiết")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Ghi log chi tiết từng chunk, highlight và tham số TTS (có thể giảm hiệu năng).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                    .onChange(of: isTTSVerboseLoggingEnabled) { _, newValue in
                        AppLogger.shared.isTTSVerboseLoggingEnabled = newValue
                    }
                }
            }

            Section {
                LabeledContent("File đang mở", value: "\(openFileCount) / \(openFileLimit)")
                Toggle("Tự dọn file mở thừa", isOn: $isFDSweeperEnabled)
            } header: {
                SectionHelpHeader("Chẩn Đoán", paragraphs: ["Nghe TTS lâu ở nền có thể làm app mở thừa hàng nghìn file rồi lỗi đọc chương. Bật thì app tự đóng các bản mở thừa (không đụng database). Tắt nếu thấy lỗi lạ."])
            }

            sessionsSection
            actionsSection
        }.glassSheetRows() }
        .backPageTitle("Ghi log hệ thống")
        .onAppear(perform: reload)
        .sheet(item: $exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Xóa Nhật Ký", isPresented: $showingClearLogAlert) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa", role: .destructive) {
                AppLogger.shared.clear()
                selected.removeAll()
                hasLoaded = false
                reload()
            }
        } message: {
            Text("Xoá tất cả phiên log? Thao tác này không thể hoàn tác.")
        }
    }

    // MARK: - Phiên

    private var sessionsSection: some View {
        Section {
            if sessions.isEmpty {
                Text(hasLoaded ? "Chưa có phiên log nào." : "Đang đọc…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        } header: {
            SectionHelpHeader(
                "Phiên · \(sessions.count) / \(AppLogger.keptSessions) · \(formatBytes(storeBytes))",
                paragraphs: [
                    "Mỗi lần mở app là một phiên, ghi kèm bản build, máy, iOS, nhiệt, RAM, ổ trống và trình đọc TTS lúc mở. Giữ \(AppLogger.keptSessions) phiên gần nhất, tối đa 30 MB.",
                    "**Chết đột ngột**: phiên kết thúc khi app đang mở (crash hoặc bị đóng) — phiên kế tiếp ghi lại giờ và dòng cuối của nó.",
                    "Chọn phiên rồi **Xuất** ⇒ một file .txt để gửi."
                ]
            )
        }
    }

    private func sessionRow(_ session: AppLogger.SessionSummary) -> some View {
        let isSelected = selected.contains(session.id)
        return Button {
            if isSelected { selected.remove(session.id) } else { selected.insert(session.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(Self.dayTime(session.startedAt)) · \(session.versionDisplay)")
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if session.diedAbruptly {
                            // `.red` literal có chủ ý: cảnh báo, không theo màu nhấn.
                            Text("Chết đột ngột")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.18), in: Capsule())
                        }
                    }
                    subtitle(session)
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ session: AppLogger.SessionSummary) -> Text {
        let prefix = (session.isCurrent ? "Đang ghi · " : "") + "\(session.lineCount.formatted()) dòng · "
        let errors = session.errorCount > 0
            ? Text("\(session.errorCount.formatted()) lỗi").foregroundColor(.red)
            : Text("không lỗi").foregroundColor(.secondary)
        return Text(prefix).foregroundColor(.secondary) + errors
    }

    // MARK: - Thao tác

    private var deletableSelection: [Int64] {
        sessions.filter { selected.contains($0.id) && !$0.isCurrent }.map(\.id)
    }

    private var actionsSection: some View {
        Section(header: Text("Thao Tác")) {
            Button(action: exportSelected) {
                HStack {
                    Label(
                        selected.isEmpty ? "Xuất phiên (.txt)" : "Xuất \(selected.count) phiên (.txt)",
                        systemImage: "square.and.arrow.up"
                    )
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            if !deletableSelection.isEmpty {
                Button(role: .destructive) {
                    AppLogger.shared.deleteSessions(deletableSelection) {
                        selected.subtract(deletableSelection)
                        reload()
                    }
                } label: {
                    Label("Xoá \(deletableSelection.count) phiên", systemImage: "trash")
                }
            }
            Button(role: .destructive) {
                showingClearLogAlert = true
            } label: {
                Label("Xoá tất cả", systemImage: "trash")
            }
        }
    }

    private func exportSelected() {
        guard !isExporting else { return }
        guard !selected.isEmpty else {
            ToastManager.shared.show(message: "Chọn phiên muốn xuất", type: .info)
            return
        }
        isExporting = true
        AppLogger.shared.exportSessions(Array(selected)) { url in
            isExporting = false
            guard let url else {
                ToastManager.shared.show(message: "Không xuất được log", type: .error)
                return
            }
            exportFile = ExportFile(url: url)
        }
    }

    // MARK: - Đọc

    private func reload() {
        let counts = FileDescriptorCensus.openCount()
        openFileCount = counts.open
        openFileLimit = counts.limit
        AppLogger.shared.loadSessions { rows, bytes in
            sessions = rows
            storeBytes = bytes
            // Lần đầu: chọn sẵn phiên đang ghi.
            if !hasLoaded, let current = rows.first(where: \.isCurrent) {
                selected.insert(current.id)
            }
            selected.formIntersection(rows.map(\.id))
            hasLoaded = true
        }
    }

    /// "Hôm nay 21:12" / "Hôm qua 22:05" / "12/11 09:30".
    private static func dayTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hôm nay \(time)" }
        if calendar.isDateInYesterday(date) { return "Hôm qua \(time)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
