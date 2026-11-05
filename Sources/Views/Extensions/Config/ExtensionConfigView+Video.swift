import SwiftUI

/// Nhóm **Video** của màn Cấu hình tiện ích — chỉ tiện ích loại video (`SearchExtensionScopePolicy.kind(of:) == .video`)
/// đã cài. Một bộ chọn "Vuốt xuống trình phát" ánh xạ `Extension.videoMinimizeOverride`:
/// "Theo cài đặt chung (…)" = `nil`, "Thu nhỏ vào hub" / "Hình trong hình" = raw value của `VideoMinimizeStyle`.
///
/// Nhãn "Theo cài đặt chung (…)" ghi giá trị chung đang áp cho tiện ích này: tiện ích 18+ (`ExtensionNsfwClassifier`)
/// theo dòng "Phim 18+", còn lại theo "Phim thường" (Cài đặt › Đọc & Nghe › Video). Phim tự đánh dấu 18+ của một tiện
/// ích thường vẫn theo dòng "Phim 18+" khi tiện ích không ghi đè (`VideoMinimizePolicy`).
///
/// Lưu **ngay** qua `ExtensionTransactionCoordinator.setVideoMinimizeOverride` (mẫu `+Nsfw`), áp từ lần vuốt kế tiếp.
extension ExtensionConfigView {
    /// Tag của Picker — enum thay `String?` để không vướng bẫy tag `Optional` không khớp kiểu (chọn mà không ăn).
    enum VideoMinimizeChoice: Hashable {
        case global
        case style(VideoMinimizeStyle)

        init(overrideValue: String?) {
            if let raw = overrideValue, let style = VideoMinimizeStyle(rawValue: raw) {
                self = .style(style)
            } else {
                self = .global
            }
        }

        var overrideValue: String? {
            switch self {
            case .global: return nil
            case .style(let style): return style.rawValue
            }
        }
    }

    @ViewBuilder
    internal var videoSection: some View {
        if current.isInstalled, SearchExtensionScopePolicy.kind(of: current) == .video {
            Section {
                Picker("Vuốt xuống trình phát", selection: videoMinimizeBinding) {
                    Text("Theo cài đặt chung (\(globalVideoMinimizeStyle.title))").tag(VideoMinimizeChoice.global)
                    ForEach(VideoMinimizeStyle.allCases) { style in
                        Text(style.title).tag(VideoMinimizeChoice.style(style))
                    }
                }
                .pickerStyle(.menu)
            } header: {
                SectionHelpHeader("Video", paragraphs: [
                    "**Vuốt xuống trình phát**: vuốt xuống khung phim ở màn dọc thì thu nhỏ vào hub hoặc bật Hình trong hình. Nút ⌄ luôn thu nhỏ vào hub.",
                    "«Theo cài đặt chung» lấy dòng «Phim thường» hoặc «Phim 18+» ở Cài đặt › Đọc & Nghe › Video.",
                    "Không bật được Hình trong hình (phim nhúng, phim chưa tải xong) thì thu nhỏ vào hub."
                ])
            }
        }
    }

    /// Giá trị chung đang áp nếu bỏ ghi đè: tiện ích 18+ ⇒ dòng "Phim 18+".
    private var globalVideoMinimizeStyle: VideoMinimizeStyle {
        VideoMinimizePolicy.globalStyle(nsfw: ExtensionNsfwClassifier.isNsfw(current))
    }

    /// Như `nsfwChoiceBinding`: chụp giá trị trong lượt vẽ, ghi qua `MainActor.assumeIsolated`.
    private var videoMinimizeBinding: Binding<VideoMinimizeChoice> {
        let choice = VideoMinimizeChoice(overrideValue: current.videoMinimizeOverride)
        let packageId = ext.packageId
        let name = current.name
        return Binding(
            get: { choice },
            set: { newChoice in
                guard newChoice != choice else { return }
                let overrideValue = newChoice.overrideValue
                MainActor.assumeIsolated { Self.saveVideoMinimizeOverride(packageId: packageId, name: name, overrideValue) }
            }
        )
    }

    @MainActor
    static func saveVideoMinimizeOverride(packageId: String, name: String, _ value: String?) {
        switch ExtensionTransactionCoordinator.shared.setVideoMinimizeOverride(packageId: packageId, value) {
        case .success:
            let note = value.flatMap { VideoMinimizeStyle(rawValue: $0)?.title } ?? "theo cài đặt chung"
            AppLogger.shared.log("🎬 [ExtConfig] \(name): vuốt xuống trình phát ⇒ \(note)")
        case .failure(let err):
            AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu kiểu vuốt xuống của \(name): \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không lưu được kiểu vuốt xuống: \(err.localizedDescription)", type: .error)
        }
    }
}
