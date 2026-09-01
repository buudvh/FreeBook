import Foundation

public enum ExtensionType {
    public static let novel = "novel"
    public static let chineseNovel = "chinese_novel"
    public static let comic = "comic"
    public static let tts = "tts"
    /// Nguồn truyện JSON của Legado (書源) — chạy bằng `LegadoSourceRuntime` thay vì JSExecutor.
    public static let legado = "legado"
}
