import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// File `.txt` chia sẻ kết quả của màn thử VieNeu Turbo (1.3.878) — thay cho nút "Sao chép": dán một khối chữ dài vào
/// chat rất cực, gửi file qua Files / AirDrop / Telegram thì một chạm.
///
/// Nội dung dựng **đúng lúc bấm chia sẻ** (như `ThermalCSVExport`), từ trạng thái của `VieNeuTurboLab` — không có file
/// nằm sẵn trên đĩa, và `body` của view không phải dựng chuỗi dài mỗi lần vẽ lại.
struct VieNeuTurboReportFile: Transferable {
    enum Kind: Sendable {
        /// Số đo của lượt "Đọc thử".
        case sample
        /// Tổng kết + từng phút + mọi đoạn của lượt "Đọc liên tục".
        case soak
        /// Báo cáo phép thử P1 "So EP cho Nano" (`VieNeuNanoEPProbe`).
        case epProbe
    }

    let kind: Kind
    /// Tên gợi ý, chốt lúc vẽ nút (hàm `suggestedFileName` không chạy bất đồng bộ được).
    let fileName: String

    init(kind: Kind, engineName: String) {
        self.kind = kind
        let prefix: String
        switch kind {
        case .sample: prefix = "doc-thu"
        case .soak: prefix = "doc-lien-tuc"
        case .epProbe: prefix = "so-ep"
        }
        fileName = "vieneu-\(engineName)-\(prefix)-\(Self.fileStamp.string(from: Date())).txt"
    }

    /// Ghi báo cáo ra **file `.txt` thật** trong thư mục tạm rồi trả URL để đưa vào bảng chia sẻ (1.3.890).
    ///
    /// Nút chia sẻ cũ (`ShareLink` + `DataRepresentation`) đưa cho app nhận **dữ liệu chữ dựng lúc bấm**, không phải
    /// một file: AirDrop / Lưu vào Tệp / Telegram gốc tự đóng gói thành file, nhưng Nicegram báo "đã gửi" mà không có
    /// file. File thật + `UIActivityViewController` là cách các chỗ khác của app (sao lưu, xuất từ điển) đang dùng.
    @MainActor
    static func writeTemporaryFile(kind: Kind, engineName: String) -> URL? {
        let file = VieNeuTurboReportFile(kind: kind, engineName: engineName)
        let body = VieNeuTurboLab.shared.reportText(for: kind)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VieNeuLabShare", isDirectory: true)
        let url = directory.appendingPathComponent(file.fileName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data((header() + "\n\n" + body + "\n").utf8).write(to: url, options: .atomic)
            return url
        } catch {
            AppLogger.shared.log("❌ [VieNeuTurbo] Không ghi được file chia sẻ: \(error.localizedDescription)")
            return nil
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in
            let body = await MainActor.run { VieNeuTurboLab.shared.reportText(for: file.kind) }
            return Data((Self.header() + "\n\n" + body + "\n").utf8)
        }
        .suggestedFileName { $0.fileName }
    }

    /// Đầu file: app, máy, giờ, nhiệt — file gửi đi rồi vẫn biết đo ở đâu, lúc nào.
    static func header(date: Date = Date()) -> String {
        """
        Tàng Công Các · màn thử VieNeu Turbo
        bản app      \(AppVersionInfo.display)
        máy          \(deviceModel)
        lúc          \(timeFormatter.string(from: date))
        nhiệt        \(VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState))
        """
    }

    /// Mã máy kiểu `iPhone12,1` (= iPhone 11) — đọc từ `uname`, không cần UIKit ở tầng Services.
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // giờ 24h + lịch Gregorian bất kể cài đặt máy
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
