import Foundation

/// Giọng của trình đọc **vtts Việt–Anh (Offline)**:
/// - **Có sẵn trong app**: 2 giọng bản M của release v0.4.0, lưu sẵn trong repo (`Vendor/vtts/assets/vtts`) và đóng vào IPA
///   (thư mục `vtts/` của bundle). Không tải / xoá: chỉ chọn.
/// - **Tự nhập** (1.3.1043, anh Bửu: "tích hợp giọng Ngọc Huyền vào app"): file `.vtts` người dùng chọn từ Tệp, chép vào
///   `FreeBook/TTS/Vtts/` (`VttsImportedVoiceRepository`). Giọng train riêng (dữ liệu giấy phép phi thương mại / không chính
///   thức) chỉ nằm trên máy người dùng — không vào repo công khai, CI hay IPA.
///
/// `id` là giá trị lưu trong cài đặt (`vttsVoice`) và là tham số `voice` của `LocalTTSEngine` (`VttsTTSService`) — đổi id
/// của giọng có sẵn là mất lựa chọn đã lưu. Giọng tự nhập: `file:<tên file>`. Id lạ (giọng của trình đọc khác lọt sang,
/// dữ liệu cũ, file tự nhập đã xoá) ⇒ `resolve` trả giọng mặc định.
struct VttsVoice: Hashable, Identifiable, Sendable {
    enum Source: Hashable, Sendable {
        /// Tên file model trong thư mục `vtts` của bundle — giữ đúng tên ở release upstream
        /// (`Scripts/ci/check_vtts_assets.sh` kiểm SHA256 theo tên này với `SHA256SUMS` của release).
        case bundled(fileName: String)
        /// Tên file trong `FreeBook/TTS/Vtts/` (luôn đuôi `.vtts`).
        case imported(fileName: String)
    }

    let id: String
    /// Tên hiện ở Picker / sheet Giọng đọc.
    let displayName: String
    let source: Source
    /// Mức tăng âm lượng (dB) cho đoạn quá ngắn để đo (`VttsLoudness`): chênh lệch giữa mốc −14 dBFS và mức RMS lúc có
    /// tiếng **sau bước chỉnh tiếng** đo trên đoạn truyện dài của CI (1.3.1036: `nu-10` −24,7, `nam-1` −21,0 dBFS), làm
    /// tròn xuống nửa dB. Giọng tự nhập chưa đo ⇒ `importedLoudnessGainDb`.
    let defaultLoudnessGainDb: Float

    static let nu10 = VttsVoice(
        id: "nu-10", displayName: "Nữ · nu-10",
        source: .bundled(fileName: "vtts-vien-nu10-m-v0.4.q8.vtts"), defaultLoudnessGainDb: 10.5
    )
    static let nam1 = VttsVoice(
        id: "nam-1", displayName: "Nam · nam-1",
        source: .bundled(fileName: "vtts-vien-nam1-m-v0.4.q8.vtts"), defaultLoudnessGainDb: 7
    )

    /// Giọng đóng sẵn trong app, theo thứ tự hiện.
    static let bundled: [VttsVoice] = [.nu10, .nam1]
    static let defaultVoice: VttsVoice = .nu10

    /// Tiền tố id của giọng tự nhập.
    static let importedIdPrefix = "file:"
    /// Đuôi file model vtts.
    static let fileExtension = "vtts"
    /// Mức tăng cho đoạn ngắn của giọng tự nhập — giữa hai giọng có sẵn (chưa đo được giọng lạ).
    static let importedLoudnessGainDb: Float = 9

    var isImported: Bool {
        if case .imported = source { return true }
        return false
    }

    /// Tên file model (trong bundle hoặc trong thư mục giọng tự nhập) — cho log.
    var fileName: String {
        switch source {
        case .bundled(let name), .imported(let name): return name
        }
    }

    /// Dòng phụ của hàng giọng có sẵn: ngôn ngữ đọc được + dung lượng model (2 580 320 byte mỗi giọng). Giọng tự nhập dựng
    /// dòng phụ theo dung lượng đo trên đĩa (`VttsImportedVoiceRepository.sizeText`).
    static let bundledDetail = "Việt + Anh · 2,6 MB"

    /// Giọng tự nhập ứng với file `fileName` (đã có đuôi `.vtts`): tên hiện = tên file bỏ đuôi.
    static func imported(fileName: String) -> VttsVoice {
        let name = (fileName as NSString).deletingPathExtension
        return VttsVoice(
            id: importedIdPrefix + fileName,
            displayName: name.isEmpty ? fileName : name,
            source: .imported(fileName: fileName),
            defaultLoudnessGainDb: importedLoudnessGainDb
        )
    }

    /// Giọng ứng với id đã lưu: giọng có sẵn ⇒ giọng tự nhập còn file trên máy ⇒ giọng mặc định. Chỉ `stat` một file ⇒
    /// gọi được ở mọi luồng.
    static func resolve(_ id: String) -> VttsVoice {
        if let match = bundled.first(where: { $0.id == id }) { return match }
        if id.hasPrefix(importedIdPrefix) {
            let fileName = String(id.dropFirst(importedIdPrefix.count))
            if VttsImportedVoiceRepository.fileExists(fileName: fileName) { return imported(fileName: fileName) }
        }
        return defaultVoice
    }
}
