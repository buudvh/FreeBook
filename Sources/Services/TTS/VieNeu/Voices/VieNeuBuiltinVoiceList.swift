import Foundation

/// Danh sách giọng VieNeu **dựng sẵn trong app** (1.3.899) — để sheet chọn giọng hiện đủ hàng (kèm nút ⬇) **trước khi**
/// tải gì: tên + mô tả 11 giọng Nano nằm trong `voices_v3_nano.json` (2,3 MB, thuộc gói model 347 MB), 25 giọng Turbo
/// trong `manifest.json` của model Turbo. Có file trên máy thì `VieNeuVoiceDirectory` đọc file, danh sách này chỉ để lấp.
///
/// Chép nguyên văn từ kho mirror @ `VieNeuModelMirror.revision` (`nano/voices_v3_nano.json`,
/// `turbo/gguf/voices/manifest.json`). **Đổi `VieNeuModelMirror.revision` thì chép lại danh sách này.**
enum VieNeuBuiltinVoiceList {
    struct NanoVoice: Sendable {
        let name: String
        /// Như trường `description` của catalog: "Nữ · Bắc · Phong cách tin tức".
        let description: String
    }

    /// `default_voice` của `voices_v3_nano.json`.
    static let nanoDefaultName = "Minh Quân"

    static let nano: [NanoVoice] = [
        NanoVoice(name: "Adam", description: "Nam · Nam · Giọng đọc tự nhiên"),
        NanoVoice(name: "Ái Hân", description: "Nữ · Nam · Phong cách tin tức"),
        NanoVoice(name: "Mỹ Duyên", description: "Nữ · Bắc · Phong cách đọc truyện"),
        NanoVoice(name: "Đức Trí", description: "Nam · Bắc · Phong cách đọc truyện"),
        NanoVoice(name: "Hữu Quân", description: "Nam · Bắc · Phong cách tin tức"),
        NanoVoice(name: "Xuân Tiên", description: "Nữ · Bắc · Phong cách tin tức"),
        NanoVoice(name: "Mai Anh", description: "Nữ · Bắc · Phong cách tin tức"),
        NanoVoice(name: "Trúc Ly", description: "Nữ · Bắc · Phong cách tự nhiên"),
        NanoVoice(name: "Anh Khôi", description: "Nam · Bắc · Phong cách kể chuyện"),
        NanoVoice(name: "Minh Quân", description: "Nam · Bắc · Phong cách tự nhiên"),
        NanoVoice(name: "Mạnh Dũng", description: "Nam · Bắc · Phong cách tự nhiên")
    ]

    /// Thứ tự như manifest (10 giọng ⭐ trước). `frames` = số khung 80 ms của mẫu tham chiếu.
    static let turbo: [VieNeuTurboVoiceManifest.Voice] = [
        turboVoice("adam_bua", "Adam bựa", "⭐ Adam bựa — Nam · Bắc · Phong cách tự nhiên", 91),
        turboVoice("truc_ly", "Trúc Ly", "⭐ Trúc Ly — Nữ · Bắc · Phong cách tự nhiên", 59),
        turboVoice("anh_khoi", "Anh Khôi", "⭐ Anh Khôi — Nam · Bắc · Phong cách kể chuyện", 53),
        turboVoice("mai_anh", "Mai Anh", "⭐ Mai Anh — Nữ · Bắc · Phong cách tin tức", 73),
        turboVoice("minh_quan_pro", "Minh Quân Pro", "⭐ Minh Quân Pro — Nam · Bắc · Phong cách tự nhiên", 68),
        turboVoice("thuy_dung", "Thùy Dung", "⭐ Thùy Dung — Nữ · Nam · Phong cách tin tức", 54),
        turboVoice("thien_tam_duc", "Thiền Tâm Đức", "⭐ Thiền Tâm Đức — Nam · Bắc · Phong cách kể chuyện", 98),
        turboVoice("ngoc_huyen", "Ngọc Huyền", "⭐ Ngọc Huyền — Nữ · Bắc · Giọng đọc tự nhiên", 63),
        turboVoice("quang_son", "Quang Sơn", "⭐ Quang Sơn — Nam · Trung · Phong cách tự nhiên", 43),
        turboVoice("ngoc_tran", "Ngọc Trân", "⭐ Ngọc Trân — Nữ · Trung · Phong cách tự nhiên", 45),
        turboVoice("minh_duc", "Minh Đức", "Minh Đức — Nam · Bắc · Phong cách tin tức", 50),
        turboVoice("pham_tuyen", "Phạm Tuyên", "Phạm Tuyên — Nam · Bắc · Phong cách tự nhiên", 62),
        turboVoice("thai_son", "Thái Sơn", "Thái Sơn — Nam · Nam · Phong cách kể chuyện", 49),
        turboVoice("xuan_vinh", "Xuân Vĩnh", "Xuân Vĩnh — Nam · Bắc · Phong cách tự nhiên", 12),
        turboVoice("thanh_binh", "Thanh Bình", "Thanh Bình — Nam · Bắc · Phong cách kể chuyện", 42),
        turboVoice("ngoc_linh", "Ngọc Linh", "Ngọc Linh — Nữ · Bắc · Phong cách kể chuyện", 58),
        turboVoice("doan_trang", "Đoan Trang", "Đoan Trang — Nữ · Bắc · Phong cách tự nhiên", 57),
        turboVoice("thuc_doan", "Thục Đoan", "Thục Đoan — Nữ · Nam · Phong cách kể chuyện", 39),
        turboVoice("minh_triet", "Minh Triết", "Minh Triết — Nam · Nam · Phong cách tin tức", 56),
        turboVoice("my_duyen", "Mỹ Duyên", "Mỹ Duyên — Nữ · Nam · Phong cách đọc truyện", 74),
        turboVoice("quynh_anh", "Quỳnh Anh", "Quỳnh Anh — Nữ · Bắc · Phong cách đọc truyện", 70),
        turboVoice("duc_tri", "Đức Trí", "Đức Trí — Nam · Nam · Phong cách đọc truyện", 76),
        turboVoice("kim_thanh", "Kim Thanh", "Kim Thanh — Nữ · Nam · Phong cách đọc truyện", 72),
        turboVoice("adam", "Adam", "Adam — Nam · Nam · Giọng đọc tự nhiên", 38),
        turboVoice("manh_dung", "Mạnh Dũng", "Mạnh Dũng — Nam · Bắc · Phong cách tự nhiên", 57)
    ]

    private static func turboVoice(_ id: String, _ name: String, _ label: String, _ frames: Int) -> VieNeuTurboVoiceManifest.Voice {
        VieNeuTurboVoiceManifest.Voice(id: id, name: name, label: label, frames: frames)
    }
}
