import Foundation

/// Danh sách ô Server của tập đang phát cho `VideoPlayerOptionGrid` — dùng chung cho ngăn kéo `⋯` (`VideoPlayerTopBar`)
/// và lưới Server của màn xem (`VideoWatchServerGrid`).
///
/// "Bản tải" (+ "Trực tuyến" khi đang phát bản tải mà chưa nạp server) đứng đầu, rồi từng server; chọn server nào thì
/// nhớ theo tên cho cả bộ phim (`VideoPlaybackSession.selectServer`).
@MainActor
enum VideoServerOptions {
    static func make(session: VideoPlaybackSession) -> [VideoPlayerOptionGrid.Option] {
        var options: [VideoPlayerOptionGrid.Option] = []
        if session.hasOfflineCopy {
            options.append(.init(id: "offline", title: "Bản tải", systemImage: "arrow.down.circle.fill", isSelected: session.isPlayingOffline) {
                session.playOffline()
            })
            if session.servers.isEmpty {
                options.append(.init(id: "online", title: "Trực tuyến", isSelected: false) { session.playOnline() })
            }
        }
        for (index, server) in session.servers.enumerated() {
            options.append(.init(
                id: "server-\(index)",
                title: server.title.isEmpty ? "Server \(index + 1)" : server.title,
                isSelected: !session.isPlayingOffline && index == session.selectedServerIndex
            ) {
                session.selectServer(at: index)
            })
        }
        return options
    }
}
