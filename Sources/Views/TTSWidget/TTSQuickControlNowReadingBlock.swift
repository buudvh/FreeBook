import SwiftUI

/// Câu đang đọc + vạch tiến độ chương của `TTSQuickControlSheet` (tách khỏi sheet từ 2026-11-19 — trước đó là
/// `NowReadingBlock` lồng trong sheet). View riêng giữ `TTSQuickControlNowReading` để chỉ khối này vẽ lại theo từng đoạn.
///
/// Kéo vạch để tua theo **đoạn** (anh Bửu: "không tua thời gian mà tua theo đoạn", duyệt mockup): đang kéo ⇒ bong bóng
/// "Đoạn N/M" trên núm + câu đầu của đoạn đích thay vào dòng trích; thả tay mới nhảy (`TTSManager.seekToParagraph`) — được
/// cả khi đang tạm dừng (chỉ dời chỗ, không tự phát). Dưới vạch giữ badge nhiệt / dự phòng / engine / RTF bên trái và "N/M"
/// (thang đoạn) bên phải.
struct TTSQuickControlNowReadingBlock: View {
    @StateObject private var reader = TTSQuickControlNowReading()
    /// Vị trí đang kéo `0…1`; `nil` = không kéo.
    @State private var scrubFraction: Double?

    var body: some View {
        let snapshot = reader.snapshot
        let target = scrubFraction.flatMap { reader.ordinal(forFraction: $0) }
        let quote = target.flatMap { reader.entry(atOrdinal: $0)?.sentence } ?? snapshot.sentence
        VStack(alignment: .leading, spacing: 8) {
            Text(quote.isEmpty ? " " : "“\(quote)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            TTSParagraphSeekBar(
                progress: scrubFraction ?? snapshot.fraction,
                isEnabled: snapshot.total > 0,
                bubbleText: target.map { "Đoạn \($0)/\(snapshot.total)" },
                onScrubBegan: { scrubFraction = snapshot.fraction },
                onScrubChanged: { scrubFraction = $0 },
                onScrubEnded: {
                    if let fraction = scrubFraction, let ordinal = reader.ordinal(forFraction: fraction) {
                        reader.seek(toOrdinal: ordinal)
                    }
                    scrubFraction = nil
                }
            )
            HStack {
                // Mức nhiệt của máy (1.3.931) — chỗ trống bên trái "N/M".
                TTSThermalBadge()
                // Đoạn đọc bằng giọng dự phòng vì TTS online lỗi (1.3.945).
                if let fallback = snapshot.fallbackEngine {
                    TTSFallbackBadge(engine: fallback)
                }
                // Model + tăng tốc của đoạn đang phát (VieNeu, 1.3.942).
                if let engine = snapshot.engineLabel {
                    TTSEngineBadge(label: engine)
                }
                // RTF của đoạn đang phát (VieNeu hoặc Piper, 1.3.954).
                if let rtf = snapshot.rtf {
                    TTSRTFBadge(rtf: rtf)
                }
                Spacer(minLength: 8)
                Text(snapshot.total > 0 ? "\(snapshot.position)/\(snapshot.total)" : " ")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}
