import Foundation

/// Giọng của trình đọc **vtts Việt–Anh (Offline)**:
/// - **Có sẵn trong app**: `nu-10` bản M của release vtts + giọng FreeBook tự train Ngọc Huyền (1.3.1044), lưu sẵn trong
///   repo (`Vendor/vtts/assets/vtts`) và đóng vào IPA (thư mục `vtts/` của bundle). Không tải / xoá: chỉ chọn. Giọng
///   `nam-1` (release) và `google-dich` (tự train, 1.3.1046) đã gỡ ở 1.3.1135 (anh Bửu: "bỏ giọng nam và google đi") —
///   ai đang chọn chúng thì `resolve` trả giọng mặc định; bản sao file ở máy anh Bửu, cần thì nhập lại bằng "Nhập .vtts".
/// - **Tự nhập** (1.3.1043): file `.vtts` người dùng chọn từ Tệp, chép vào `FreeBook/TTS/Vtts/`
///   (`VttsImportedVoiceRepository`).
///
/// `id` là giá trị lưu trong cài đặt (`vttsVoice`) và là tham số `voice` của `LocalTTSEngine` (`VttsTTSService`) — đổi id
/// của giọng có sẵn là mất lựa chọn đã lưu. Giọng tự nhập: `file:<tên file>`. Id lạ (giọng của trình đọc khác lọt sang,
/// dữ liệu cũ, file tự nhập đã xoá) ⇒ `resolve` trả giọng mặc định.
struct VttsVoice: Hashable, Identifiable, Sendable {
    enum Source: Hashable, Sendable {
        /// Tên file model trong thư mục `vtts` của bundle — giọng của release giữ đúng tên upstream
        /// (`Scripts/ci/check_vtts_assets.sh` kiểm SHA256 theo tên này với `SHA256SUMS` của release; giọng tự train theo
        /// `LOCAL_SHA256SUMS`).
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
    /// Ghi nguồn dữ liệu train mà giấy phép bắt buộc — thay dòng phụ của hàng giọng có sẵn (`bundledRowDetail`). `nil` =
    /// giọng của release vtts (Apache-2.0, ghi ở `Vendor/vtts/THIRD_PARTY_NOTICES.md`) và giọng tự nhập.
    let credit: String?

    /// File của release vtts `v0.11.0` (1.3.1052). `nu-10` M là model v0.9.1: giai đoạn joint 80k bước thay 20k — upstream
    /// đo UTMOS vi 2,73 → 3,11, bớt lớp ồn "buzzy" của bản 20k; cùng kiến trúc / bộ token. Mức tăng 10,5 đo trên bản
    /// v0.4, chưa đo lại.
    static let nu10 = VttsVoice(
        id: "nu-10", displayName: "Nữ · nu-10",
        source: .bundled(fileName: "vtts-vien-nu10-m-v0.11.q8.vtts"), defaultLoudnessGainDb: 10.5, credit: nil
    )
    /// Giọng FreeBook tự train (1.3.1044, anh Bửu: "Sao ko tích hợp trực tiếp vào app, giọng hợp lệ mà"): bản M chưng cất
    /// từ thầy VITS train trên dataset `pnnbao-ump/ngochuyen_voice` (**CC BY-NC 4.0** ⇒ ghi nguồn ở dòng phụ, app không thu
    /// phí) + câu Anh / câu trộn nhân bản bằng VoxCPM2 (Apache-2.0). Từ 1.3.1131 là bản chưng cất joint **80k** bước của
    /// lượt Kaggle `vtts-k6` (thay bản joint 20k của `vtts-k4`; UTMOS tiếng Việt 2,28 → 2,62). Mức tăng đo trên 6 câu mẫu
    /// của bản k4 (−22,0 dBFS sau bước chỉnh tiếng), **chưa đo lại** trên bản k6, chưa đo trên đoạn truyện dài của CI như
    /// `nu-10`.
    static let ngocHuyen = VttsVoice(
        id: "ngoc-huyen", displayName: "Nữ · Ngọc Huyền",
        source: .bundled(fileName: "vtts-ngochuyen-m-k6.q8.vtts"), defaultLoudnessGainDb: 7.5,
        credit: "pnnbao-ump · CC BY-NC 4.0"
    )

    /// Giọng đóng sẵn trong app, theo thứ tự hiện.
    static let bundled: [VttsVoice] = [.nu10, .ngocHuyen]
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

    /// Dòng phụ của hàng giọng có sẵn trong sheet chọn giọng: ghi nguồn nếu có (dòng phụ chỉ một dòng ⇒ thay hẳn, nối thêm
    /// sẽ bị cắt mất phần giấy phép), không thì `bundledDetail`.
    var bundledRowDetail: String {
        credit ?? Self.bundledDetail
    }

    /// Giọng tự nhập ứng với file `fileName` (đã có đuôi `.vtts`): tên hiện = tên file bỏ đuôi.
    static func imported(fileName: String) -> VttsVoice {
        let name = (fileName as NSString).deletingPathExtension
        return VttsVoice(
            id: importedIdPrefix + fileName,
            displayName: name.isEmpty ? fileName : name,
            source: .imported(fileName: fileName),
            defaultLoudnessGainDb: importedLoudnessGainDb,
            credit: nil
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
