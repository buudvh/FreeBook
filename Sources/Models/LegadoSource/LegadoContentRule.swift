import Foundation

/// `ContentRule.kt` — rule trang nội dung chương.
///
/// Các trường ngoài phạm vi hỗ trợ (`imageDecode`, `payAction`, `callBackJs`, `webJs`) vẫn được đọc
/// để `LegadoCompatibilityReport` báo cho người dùng biết nguồn cần tính năng chưa làm, thay vì trả
/// nội dung sai một cách im lặng.
public struct LegadoContentRule {
    public let content: String?
    public let subContent: String?
    public let title: String?
    public let nextContentUrl: String?
    public let replaceRegex: String?
    public let sourceRegex: String?
    public let imageStyle: String?
    public let webJs: String?
    public let imageDecode: String?
    public let payAction: String?
    public let callBackJs: String?

    public init(json: [String: Any]?) {
        let dict = json ?? [:]
        content = LegadoJSON.string(dict["content"])
        subContent = LegadoJSON.string(dict["subContent"])
        title = LegadoJSON.string(dict["title"])
        nextContentUrl = LegadoJSON.string(dict["nextContentUrl"])
        replaceRegex = LegadoJSON.string(dict["replaceRegex"])
        sourceRegex = LegadoJSON.string(dict["sourceRegex"])
        imageStyle = LegadoJSON.string(dict["imageStyle"])
        webJs = LegadoJSON.string(dict["webJs"])
        imageDecode = LegadoJSON.string(dict["imageDecode"])
        payAction = LegadoJSON.string(dict["payAction"])
        callBackJs = LegadoJSON.string(dict["callBackJs"])
    }
}
