import Foundation

/// Hai danh sách `chữ Hán=nghĩa|loại|vị trí` của Lọc name local dùng **chung** màn danh sách
/// (`LocalNameFilterSuffixListView`), màn Sửa từ (`LocalNameFilterSuffixEditorSheet`) và hàng ở màn Sửa từ của màn duyệt
/// (`LocalNameFilterSuffixQuickRow`) — plan 2026-11-27-phan-loai-name L10 / L11 / mục 6–11, anh Bửu: "Đuôi bây giờ gọi hậu
/// tố đi cho đối xứng tiền tố", "Thêm tiền tố phải đầy đủ như hậu tố". Mọi chỗ khác nhau giữa hai danh sách nằm ở đây:
/// store, danh từ trên màn, mặc định khi thêm mới, luật "nằm cuối / đầu name" khi thêm từ một name, mẫu của dòng "Ví dụ",
/// lời giải thích "?". Tên type / file trong code giữ chữ `Suffix` (anh chốt: đổi tên code không đem lại gì).
enum LocalNameFilterAffixListFlavor: Hashable {
    /// Danh sách "Hậu tố" (`LocalNameFilterSuffixStore`): mục nằm **cuối** name.
    case suffix
    /// Danh sách "Tiền tố" (`LocalNameFilterPrefixStore`): mục nằm **đầu** name, chỉ ghép nghĩa trước tên Latin.
    case prefix

    var store: LocalNameFilterAffixListStore {
        switch self {
        case .suffix: return LocalNameFilterSuffixStore.shared
        case .prefix: return LocalNameFilterPrefixStore.shared
        }
    }

    /// "Hậu tố" / "Tiền tố" — tiêu đề màn danh sách, hàng ở sheet, hàng ở màn Sửa từ của màn duyệt.
    var noun: String {
        switch self {
        case .suffix: return "Hậu tố"
        case .prefix: return "Tiền tố"
        }
    }

    /// "hậu tố" / "tiền tố" — giữa câu (toast, số mục, trợ năng).
    var lowercasedNoun: String { noun.lowercased() }

    /// Badge của màn Sửa từ ("Hậu tố · chung").
    var badgeText: String { "\(noun) · chung" }

    var meaningPlaceholder: String {
        switch self {
        case .suffix: return "Nghĩa của hậu tố (trấn, thành phố, trưởng lão…)"
        case .prefix: return "Nghĩa của tiền tố (lão, tiểu…)"
        }
    }

    /// Mục mới: hậu tố đặt nghĩa sau tên (落霞镇 → Lạc Hà trấn), tiền tố trước tên (老尼尔 → lão Neil).
    var defaultPosition: LocalNameFilter.MeaningPosition {
        switch self {
        case .suffix: return .after
        case .prefix: return .before
        }
    }

    /// Loại của mục mới khi màn danh sách không lọc loại nào: hậu tố Địa danh, tiền tố Nhân danh (老 / 小 của tên người).
    var defaultKind: LocalNameFilter.SuffixKind {
        switch self {
        case .suffix: return .place
        case .prefix: return .person
        }
    }

    // MARK: - Vị trí trong name

    /// Thêm từ một name (màn Sửa từ của màn duyệt): hậu tố phải là phần **cuối** name, tiền tố phần **đầu**, và chừa ≥ 1 chữ
    /// phía bên kia. `nil` = hợp lệ (luật chung còn lại — 1–6 chữ Hán, trùng khoá — do store kiểm).
    func sourceKeyError(_ key: String, name rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .suffix:
            if key == name { return "Chừa ít nhất 1 chữ phía trước hậu tố." }
            if !name.hasSuffix(key) { return "Hậu tố phải nằm cuối name." }
        case .prefix:
            if key == name { return "Chừa ít nhất 1 chữ phía sau tiền tố." }
            if !name.hasPrefix(key) { return "Tiền tố phải nằm đầu name." }
        }
        return nil
    }

    /// Phần còn lại của `name` khi bỏ mục `key` ở đúng phía (cuối với hậu tố, đầu với tiền tố); `nil` = `key` không nằm ở
    /// phía đó hoặc không còn chữ nào.
    func remainder(of rawName: String, removing key: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyLength = key.unicodeScalars.count
        guard !key.isEmpty, name.unicodeScalars.count > keyLength else { return nil }
        var view = String.UnicodeScalarView()
        switch self {
        case .suffix:
            guard name.hasSuffix(key) else { return nil }
            view.append(contentsOf: name.unicodeScalars.dropLast(keyLength))
        case .prefix:
            guard name.hasPrefix(key) else { return nil }
            view.append(contentsOf: name.unicodeScalars.dropFirst(keyLength))
        }
        return String(view)
    }

    /// Ghép mục với phần tên riêng theo đúng phía: 江海 + 市 / 老 + 尼尔.
    func word(key: String, proper: String) -> String {
        switch self {
        case .suffix: return proper + key
        case .prefix: return key + proper
        }
    }

    // MARK: - Dòng "Ví dụ"

    /// Phần tên riêng mẫu của dòng "Ví dụ" theo loại. Hậu tố: 江海 → Giang Hải (江海市), 五气 → Ngũ Khí (五气丹), 陈 → Trần
    /// (陈长老 → Trần trưởng lão). Tiền tố chỉ ghép trước **tên Latin** ⇒ mẫu luôn là tên Latin: 尼尔 → Neil (老尼尔 → lão
    /// Neil), name không phải người 佐特兰 → Zotland.
    func sample(for kind: LocalNameFilter.SuffixKind) -> (name: String, reading: String) {
        switch self {
        case .suffix:
            switch kind {
            case .place, .sect: return ("江海", "Giang Hải")
            case .term: return ("五气", "Ngũ Khí")
            case .person: return ("陈", "Trần")
            }
        case .prefix:
            switch kind {
            case .person: return ("尼尔", "Neil")
            case .place, .sect, .term: return ("佐特兰", "Zotland")
            }
        }
    }

    // MARK: - Chữ trên màn danh sách

    var emptyListText: String {
        switch self {
        case .suffix:
            return "Danh sách hậu tố đang trống: nghĩa name sẽ chỉ là phiên âm, tên người không có danh xưng. Bấm + để thêm."
        case .prefix:
            return "Danh sách tiền tố đang trống: 老尼尔 sẽ đọc Lão Ni Nhĩ thay cho lão Neil. Bấm + để thêm."
        }
    }

    var listHelpParagraphs: [String] {
        switch self {
        case .suffix:
            return [
                "Danh sách này **chỉ dùng để dịch nghĩa**. Name không phải tên người kết thúc bằng một hậu tố Địa danh / Tổ chức / Thuật ngữ (落霞**镇**, 天斗**帝国**, 五气**丹**) có nghĩa = phần tên riêng + nghĩa của hậu tố giữ nguyên chữ, đặt **sau tên** (落霞镇 → Lạc Hà trấn) hoặc **trước tên** (街 = \"phố\" · trước tên ⇒ 佐特兰街 → phố Zotland).",
                "Hậu tố **Nhân danh** là danh xưng sau tên người: lấy hậu tố dài nhất (陈太上长老 → Trần thái thượng trưởng lão, 天元圣女 → Thiên Nguyên thánh nữ). Hậu tố 1 chữ (哥, 爷…) chỉ dùng khi bộ lọc thấy ít nhất 3 tên khác nhau đứng trước nó.",
                "Việc dò và phân loại name dùng bộ hậu tố cố định trong app, không theo danh sách này — thêm hay xoá hậu tố không làm đổi số name tìm được.",
                "Danh sách dùng chung mọi truyện. \"Khôi phục mặc định\" ở menu … bỏ mọi hậu tố đã thêm, sửa hoặc xoá."
            ]
        case .prefix:
            return [
                "Danh sách này **chỉ dùng để dịch nghĩa** tên Latin có tiền tố đứng trước: 老尼尔 → lão Neil, 小伊特 → tiểu Etter. Phần sau tiền tố không ra tên Latin (từ điển, hoặc máy đoán khi bật \"Ưu tiên tên Latin\") thì giữ Hán-Việt cả cụm (小鱼 → Tiểu Ngư, 老张 → Lão Trương).",
                "Tiền tố chỉ áp cho name cùng nhóm với loại của nó: loại Nhân danh cho tên người, Địa danh / Tổ chức / Thuật ngữ cho name không phải người.",
                "Danh sách dùng chung mọi truyện. \"Khôi phục mặc định\" ở menu … bỏ mọi tiền tố đã thêm, sửa hoặc xoá."
            ]
        }
    }

    // MARK: - Hàng ở màn Sửa từ của màn duyệt

    var quickRowHelpParagraphs: [String] {
        switch self {
        case .suffix:
            return [
                "Thêm hậu tố vào danh sách **Hậu tố** ngay từ name này: chạm một đoạn cuối gợi ý (+ 街, + 兰街…) hoặc **+ Thêm hậu tố** (mở với cả cụm, thu hẹp bằng ‹ ›). Hậu tố dài 1–6 chữ, chừa ít nhất 1 chữ phía trước, có 4 loại: Địa danh, Tổ chức, Thuật ngữ, Nhân danh.",
                "Mọi hậu tố có sẵn nằm trong name (ở cuối hoặc giữa cụm) đều hiện ✓ — chạm để sửa. Chip xếp theo số chữ tăng dần. Nghĩa ghép theo hậu tố **dài nhất** ở cuối, cùng nhóm với name (dấu ●): 陈太上长老 ⇒ Trần thái thượng trưởng lão.",
                "Lưu xong, các name kết thúc bằng hậu tố đó mà nghĩa vẫn do máy ghép được ghép lại nghĩa ngay; nghĩa đã tự sửa giữ nguyên."
            ]
        case .prefix:
            return [
                "Thêm tiền tố vào danh sách **Tiền tố** ngay từ name này: chạm một đoạn đầu gợi ý (+ 老, + 老尼…) hoặc **+ Thêm tiền tố** (mở với cả cụm, thu hẹp bằng ‹ ›). Tiền tố dài 1–6 chữ, chừa ít nhất 1 chữ phía sau.",
                "Mọi tiền tố có sẵn nằm trong name (ở đầu hoặc giữa cụm) đều hiện ✓ — chạm để sửa; dấu ● là tiền tố dùng để ghép nghĩa (dài nhất ở đầu, cùng nhóm với name). Chip xếp theo số chữ tăng dần.",
                "Tiền tố chỉ dùng khi phần sau là tên Latin: 老尼尔 ⇒ lão Neil. Phần sau đọc Hán-Việt thì giữ nguyên cả cụm (小鱼 ⇒ Tiểu Ngư). Lưu xong, các name mở đầu bằng tiền tố đó mà nghĩa vẫn do máy ghép được ghép lại nghĩa ngay."
            ]
        }
    }
}
