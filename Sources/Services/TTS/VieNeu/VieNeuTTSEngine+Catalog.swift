import Foundation

/// Nạp lại **catalog giọng** của engine mà không phải dựng lại engine.
///
/// ## Vì sao cần
/// `VieNeuTTSEngine.prepareLocked` chỉ chạy **một lần** trong vòng đời engine (`guard runtime == nil else
/// { return }`) và nạp `catalog` đúng ở đó. Mà engine sống suốt vòng đời app — `VieNeuTTSService` là
/// singleton, `engine` là `let` ⇒ giọng người dùng tạo **sau** lượt nạp đầu sẽ **không bao giờ** tới được
/// engine, cho tới khi mở lại app.
///
/// Hệ quả **không hề báo lỗi**: `VieNeuTTSEngine.synthesize` dùng
/// `catalog.preset(named: voiceName) ?? catalog.defaultPreset` ⇒ giọng lạ **rơi im lặng** về giọng mặc
/// định. Người dùng tạo giọng mới rồi nghe ra **đúng giọng mặc định** trong khi UI vẫn báo thành công.
/// Đã xảy ra thật: tạo giọng xong đọc truyện nghe y như giọng mặc định, **tắt app mở lại thì đúng âm sắc**
/// — vì lúc đó engine dựng lại và catalog được nạp lại.
///
/// ## Vì sao nằm ở file riêng
/// `VieNeuTTSEngine.swift` đang **đúng trần 400 dòng** vật lý của `check_architecture.py` ⇒ không thêm
/// được dòng nào. Đổi lại phải hạ `store` / `lock` / `catalog` từ `private` xuống `internal`, vì Swift
/// giới hạn `private` theo **file** (bẫy đã cắn nhiều lần trong repo này).
extension VieNeuTTSEngine {
    /// Đọc lại catalog giọng từ đĩa — gồm cả giọng của người dùng trong `CustomVoices/`.
    ///
    /// Gọi sau **mọi** thay đổi của kho giọng: tạo mới, tạo lại embedding, đổi tên, xoá.
    ///
    /// Đọc file **ngoài** `lock` (JSON ~2,3 MB, không nên giữ khoá lâu) rồi mới gán `catalog` **trong**
    /// `lock`, để không đọc/ghi `catalog` song song với một lượt `synthesize` đang chạy.
    func refreshVoiceCatalog() throws {
        let fresh = try VieNeuVoiceCatalog.load(modelStore: store)
        lock.lock()
        defer { lock.unlock() }
        catalog = fresh
    }
}
