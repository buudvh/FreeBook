import Foundation

/// Danh mục **tìm nhanh** cho nguồn Legado không có Khám phá riêng (không khai `exploreUrl`/rule khám phá, hoặc tắt
/// `enabledExplore`) nhưng có rule tìm kiếm: tab lưới thể loại của Khám phá hiện các ô từ khoá, bấm một ô ⇒ danh sách
/// kết quả **tìm kiếm** của nguồn với từ khoá đó (phân trang như mục khám phá). Người dùng yêu cầu 2026-10-22; danh sách
/// từ khoá lấy theo danh mục tìm của tiện ích `wcshuba` (`genre.js`), bỏ các mục phân loại riêng của trang đó.
///
/// Mục tìm nhanh đi đúng đường của mục khám phá (`SourceRuntime.legadoExploreScriptName`), chỉ khác URL mang tiền tố
/// `urlPrefix` — `SourceRuntime.executeCustomScript` nhận ra và chạy luồng tìm kiếm thay vì luồng khám phá.
enum LegadoQuickSearch {
    static let urlPrefix = "legado-quick-search:"

    /// Từ khoá tiếng Trung (ô hiển thị bản dịch QT khi bật dịch, như tên thể loại của nguồn).
    static let keywords: [String] = [
        "诸天", "聊天群", "万界", "无限", "同时穿越", "轮回", "御兽",
        "修真聊天群", "霸宋", "宋书航",
        "盘龙", "吞噬", "星辰变", "沧元图",
        "牧神记", "帝尊", "魔狱玄胎",
        "神墓", "遮天", "完美世界", "圣墟",
        "凡人", "仙逆",
        "一世之尊", "孟奇", "诡秘",
        "永生", "阳神",
        "西游", "洪荒", "大奉", "庆余年",
        "斗罗", "武魂", "神印",
        "斗破", "武动", "大主宰", "元尊",
        "妖神记", "师兄啊", "全職法師", "剑来", "雪中",
        "全球高武", "万族之劫", "星门",
        "剑道独尊",
        "哈利波特", "霍格沃兹",
        "美漫", "漫威",
        "磁场转动",
        "宝可梦", "综漫", "龙珠", "火影", "木叶", "鸣人", "犬夜叉", "海贼", "妖尾", "奥特曼", "假面骑士", "骑士",
        "死神", "全職獵人", "鬼灭之刃", "美食", "柯南"
    ]

    /// Nguồn dùng danh mục tìm nhanh: có rule tìm kiếm, và không có Khám phá dùng được.
    static func applies(hasSearchRules: Bool, hasExploreRules: Bool, enabledExplore: Bool) -> Bool {
        hasSearchRules && (!hasExploreRules || !enabledExplore)
    }

    static func applies(to source: LegadoBookSource) -> Bool {
        applies(hasSearchRules: source.hasSearchRules, hasExploreRules: source.hasExploreRules,
                enabledExplore: source.enabledExplore)
    }

    /// Các ô từ khoá dưới dạng mục khám phá loại ô bấm (4 ô một hàng, giãn đều).
    static func entries() -> [LegadoEngineExploreItem] {
        keywords.map { keyword in
            LegadoEngineExploreItem(title: keyword, url: urlPrefix + keyword, flexBasisPercent: 0.25, flexGrow: 1)
        }
    }

    /// Từ khoá của mục tìm nhanh; `nil` khi `input` là URL khám phá thường.
    static func keyword(fromInput input: String) -> String? {
        guard input.hasPrefix(urlPrefix) else { return nil }
        let keyword = String(input.dropFirst(urlPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty ? nil : keyword
    }

    /// Có sang trang được không: `searchUrl` có nhắc tới `page` (placeholder `{{page}}`, biểu thức hay JS dùng `page`).
    static func supportsPaging(_ source: LegadoBookSource) -> Bool {
        source.searchUrl.range(of: "page", options: .caseInsensitive) != nil
    }
}
