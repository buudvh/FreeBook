import Foundation

extension VieNeuJapaneseDictionary {
    /// Nguồn trên HuggingFace — **cùng repo** với từ điển của NghiTTS và **cùng tên file** với bản dưới
    /// máy, nên chỉ có một cái tên phải nhớ.
    ///
    /// Vì sao không ghim sha như `VieNeuModelClient`: file này là **dữ liệu do người dùng sở hữu và sửa
    /// tiếp trong app**, không phải trọng số model. Bản tải về chỉ dùng để **trộn** (xem dưới) nên một
    /// bản mới hơn không thể làm hỏng thứ đang chạy.
    private static var remoteURL: URL? {
        URL(string: "https://huggingface.co/raikiri1498/nghitts/resolve/main/\(fileName)")
    }

    /// Tải từ điển tiếng Nhật ban đầu rồi **trộn** với bản dưới máy — **bản local thắng**.
    ///
    /// Cùng khuôn và cùng lý do với `NghiTTSClient.downloadDictionaries` (`NghiTTSClient.swift:86-98`):
    /// người dùng tự thêm/sửa phiên âm trong app, ghi thẳng bản tải về là **xoá sạch** công sức đó.
    /// Đánh đổi đã chọn: mất một bản cập nhật từ máy chủ còn hơn mất dữ liệu người dùng.
    public func downloadInitialDictionary() async throws {
        guard let url = Self.remoteURL else {
            throw NSError(
                domain: "VieNeuJapaneseDictionary",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "URL từ điển không hợp lệ."]
            )
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "VieNeuJapaneseDictionary",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Tải từ điển thất bại: HTTP \(http.statusCode). File đã được đẩy lên HuggingFace chưa?"]
            )
        }

        guard let remote = ((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String]) else {
            throw NSError(
                domain: "VieNeuJapaneseDictionary",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Dữ liệu từ điển không hợp lệ (không phải plist dạng từ điển chuỗi)."]
            )
        }

        let local = all()
        let merged = remote.merging(local) { _, kept in kept }
        try replaceAll(merged)
        AppLogger.shared.log("🗾 [VieNeuJapaneseDictionary] Trộn từ điển: \(remote.count) mục tải về + \(local.count) mục dưới máy → \(merged.count) mục")
    }
}
