import Foundation

/// Kết quả của `WebContentPolicy` cho một webview: có gắn rule list chặn quảng cáo không, có dùng chế độ máy tính
/// (UA Safari macOS + `preferredContentMode = .desktop`) không.
struct WebContentDecision: Equatable, Sendable {
    let adBlock: Bool
    let desktop: Bool
}
