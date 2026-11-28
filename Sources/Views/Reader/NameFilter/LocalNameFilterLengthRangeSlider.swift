import SwiftUI

/// Thanh kéo **hai đầu** của hàng "Độ dài name" ở sheet Lọc name local (plan 2026-11-27-phan-loai-name L15, mockup khung 5 —
/// anh Bửu: "Thêm chọn min max số từ ở màn lọc name, dạng kéo", "step min max 1 thôi"). SwiftUI không có thanh kéo hai đầu
/// ⇒ tự dựng: rãnh xám, đoạn màu nhấn giữa hai núm trắng, hàng vạch số 2 3 … 9 10+ dưới rãnh.
///
/// - Giá trị nguyên 2…10, mỗi nấc 1 chữ; đầu phải ở 10 = "10+" (không giới hạn — nơi dùng đổi thành `maxLength = nil`).
///   Hai núm được trùng nhau (min = max), không vượt nhau.
/// - **Một** `DragGesture` trên cả thanh: lúc bắt đầu chọn núm gần điểm chạm nhất; hai núm trùng nhau thì chạm hẳn bên trái
///   / phải chúng chọn núm dưới / trên, chạm ngay trên chúng thì chờ hướng kéo (nếu không, hai núm cùng ở 10 kẹt mãi). Chạm
///   một chỗ trên rãnh ⇒ núm gần nhất nhảy tới đó.
/// - Trợ năng: mỗi núm là một phần tử riêng ("Ít nhất" / "Nhiều nhất") vuốt lên / xuống để đổi
///   (`accessibilityAdjustableAction`).
/// - Giá trị ngoài 2…10 (khoá `@AppStorage` hỏng) được kẹp khi vẽ; chỉ ghi lại khi người dùng kéo.
struct LocalNameFilterLengthRangeSlider: View {
    static let bounds = 2...10

    /// Ít nhất N chữ.
    @Binding var lower: Int
    /// Nhiều nhất N chữ; `bounds.upperBound` = không giới hạn.
    @Binding var upper: Int

    private enum Thumb {
        case lower, upper
    }

    private static let thumbSize: CGFloat = 28
    private static let trackHeight: CGFloat = 4
    private static let tickRowHeight: CGFloat = 16

    @State private var activeThumb: Thumb? = nil

    /// "2 – 10+ chữ", "3 – 6 chữ", "4 chữ", "10+ chữ" — số bên phải tiêu đề hàng.
    static func rangeText(lower: Int, upper: Int) -> String {
        let range = clamped(lower: lower, upper: upper)
        let top = range.upperBound == bounds.upperBound ? "\(range.upperBound)+" : "\(range.upperBound)"
        return range.lowerBound == range.upperBound ? "\(top) chữ" : "\(range.lowerBound) – \(top) chữ"
    }

    /// Kẹp vào 2…10, min ≤ max.
    static func clamped(lower: Int, upper: Int) -> ClosedRange<Int> {
        let low = min(max(lower, bounds.lowerBound), bounds.upperBound)
        let high = min(max(upper, low), bounds.upperBound)
        return low...high
    }

    private var range: ClosedRange<Int> { Self.clamped(lower: lower, upper: upper) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let range = self.range
            let lowX = x(for: range.lowerBound, width: width)
            let highX = x(for: range.upperBound, width: width)
            let centerY = Self.thumbSize / 2
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: width, height: Self.trackHeight)
                    .position(x: width / 2, y: centerY)
                Capsule()
                    .fill(.tint)
                    .frame(width: max(highX - lowX, Self.trackHeight), height: Self.trackHeight)
                    .position(x: (lowX + highX) / 2, y: centerY)
                ForEach(Array(Self.bounds), id: \.self) { value in
                    Text(verbatim: value == Self.bounds.upperBound ? "\(value)+" : "\(value)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .fixedSize()
                        .position(x: x(for: value, width: width), y: Self.thumbSize + Self.tickRowHeight / 2 + 2)
                        .accessibilityHidden(true)
                }
                // Núm nào cần nằm trên khi trùng nhau: ở nửa phải ⇒ núm dưới (kéo sang trái được), nửa trái ⇒ núm trên.
                let lowerOnTop = range.lowerBound == range.upperBound
                    && range.lowerBound * 2 > Self.bounds.lowerBound + Self.bounds.upperBound
                thumb(.upper, value: range.upperBound)
                    .position(x: highX, y: centerY)
                    .zIndex(lowerOnTop ? 0 : 1)
                thumb(.lower, value: range.lowerBound)
                    .position(x: lowX, y: centerY)
                    .zIndex(lowerOnTop ? 1 : 0)
            }
            .frame(width: width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: Self.thumbSize + Self.tickRowHeight + 4)
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.selection, trigger: range)
    }

    // MARK: - Núm

    private func thumb(_ which: Thumb, value: Int) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
            .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
            .accessibilityElement()
            .accessibilityLabel(which == .lower ? "Ít nhất" : "Nhiều nhất")
            .accessibilityValue(which == .upper && value == Self.bounds.upperBound ? "không giới hạn" : "\(value) chữ")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(which, by: 1)
                case .decrement: step(which, by: -1)
                @unknown default: break
                }
            }
    }

    private func step(_ which: Thumb, by delta: Int) {
        let current = range
        switch which {
        case .lower: set(.lower, to: current.lowerBound + delta)
        case .upper: set(.upper, to: current.upperBound + delta)
        }
    }

    /// Ghi một núm, kẹp trong 2…10 và không vượt núm kia.
    private func set(_ which: Thumb, to value: Int) {
        let current = range
        switch which {
        case .lower:
            let next = min(max(value, Self.bounds.lowerBound), current.upperBound)
            if next != lower { lower = next }
            if upper != current.upperBound { upper = current.upperBound }
        case .upper:
            let next = max(min(value, Self.bounds.upperBound), current.lowerBound)
            if next != upper { upper = next }
            if lower != current.lowerBound { lower = current.lowerBound }
        }
    }

    // MARK: - Kéo

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if activeThumb == nil {
                    activeThumb = pickThumb(start: drag.startLocation.x, current: drag.location.x, width: width)
                }
                guard let thumb = activeThumb else { return }
                set(thumb, to: value(at: drag.location.x, width: width))
            }
            .onEnded { _ in
                activeThumb = nil
            }
    }

    /// Núm gần điểm bắt đầu chạm nhất; hai núm trùng nhau ⇒ theo phía chạm, chạm ngay trên chúng thì theo hướng kéo
    /// (chưa rõ hướng ⇒ `nil`, chờ lượt `onChanged` sau).
    private func pickThumb(start: CGFloat, current: CGFloat, width: CGFloat) -> Thumb? {
        let range = self.range
        let lowX = x(for: range.lowerBound, width: width)
        let highX = x(for: range.upperBound, width: width)
        if range.lowerBound != range.upperBound {
            return abs(start - lowX) <= abs(start - highX) ? .lower : .upper
        }
        let half = Self.thumbSize / 2
        if start < lowX - half { return .lower }
        if start > highX + half { return .upper }
        let moved = current - start
        if moved < -2 { return .lower }
        if moved > 2 { return .upper }
        return nil
    }

    /// Tâm núm của giá trị `value`: hai đầu thụt vào nửa núm để núm không tràn khỏi hàng.
    private func x(for value: Int, width: CGFloat) -> CGFloat {
        let usable = max(width - Self.thumbSize, 1)
        let steps = CGFloat(Self.bounds.upperBound - Self.bounds.lowerBound)
        return Self.thumbSize / 2 + CGFloat(value - Self.bounds.lowerBound) / steps * usable
    }

    /// Giá trị nguyên gần vị trí `x` nhất, trong 2…10.
    private func value(at x: CGFloat, width: CGFloat) -> Int {
        let usable = max(width - Self.thumbSize, 1)
        let steps = CGFloat(Self.bounds.upperBound - Self.bounds.lowerBound)
        let raw = ((x - Self.thumbSize / 2) / usable * steps).rounded()
        return min(max(Self.bounds.lowerBound + Int(raw), Self.bounds.lowerBound), Self.bounds.upperBound)
    }
}
