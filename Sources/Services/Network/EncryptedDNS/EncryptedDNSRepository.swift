import Foundation
import Network
import Observation

/// Nguồn sự thật **duy nhất** của DNS mã hoá trong app (1.3.825): áp cài đặt lên
/// `NWParameters.PrivacyContext.default` và giữ trạng thái cho màn Mạng & DNS.
///
/// - **Phạm vi**: context mặc định áp cho mọi kết nối trong tiến trình không dùng context riêng — `URLSession` (fetch của
///   tiện ích JS, Legado, ảnh bìa, ảnh truyện tranh, tải phim offline…). WebView tải mạng ở tiến trình WebKit riêng và
///   AVPlayer không có đường cấu hình ⇒ **không** ăn; Cài đặt hướng dẫn đổi DNS cho cả máy. Máy đã cài DNS mã hoá cấp
///   hệ thống thì hệ thống thắng.
/// - **Mở app** (`start`, gọi ở `FreeBookApp.init`): bật **ngay** (lạc quan — lượt mở lại truyện đọc gần nhất cần DoH
///   từ request đầu) rồi dò (`EncryptedDNSProbe`). Ngoại lệ: lần trước kết thúc ở trạng thái lùi
///   (`EncryptedDNSPolicy.lastProbeFailed`) ⇒ khởi động bằng DNS thường, dò xong mới bật.
/// - **Dò lỗi** ⇒ lùi về DNS thường, log `❌ [DNS]`. Dò lại khi mạng có lại / đổi đường mạng (Wi-Fi ↔ 4G, bật VPN),
///   khi đổi cài đặt và khi bấm "Kiểm tra lại". Mất mạng không lùi — chờ có mạng rồi dò.
/// - Đổi context mặc định giữa chừng (lùi / tắt) Apple không ghi rõ có tác dụng với kết nối mới hay không — kiểm trên máy.
@MainActor
@Observable
final class EncryptedDNSRepository {
    static let shared = EncryptedDNSRepository()

    /// Giãn trước khi dò lại sau khi đổi đường mạng (đường mới thường chưa ổn định ngay).
    private static let pathChangeProbeDelay: UInt64 = 2_000_000_000

    private(set) var state: EncryptedDNSState = .off

    /// Máy chủ mà context mặc định đang bắt buộc; `nil` = DNS thường.
    @ObservationIgnored private var appliedResolver: EncryptedDNSResolver? = nil
    @ObservationIgnored private var probeTask: Task<Void, Never>? = nil
    @ObservationIgnored private var pathMonitor: NWPathMonitor? = nil
    /// Tên các giao diện mạng của đường hiện tại; `nil` = chưa nhận cập nhật đầu tiên của `NWPathMonitor`.
    @ObservationIgnored private var pathSignature: String? = nil
    @ObservationIgnored private var hasNetwork = true
    @ObservationIgnored private var didStart = false

    private init() {}

    /// Gọi một lần lúc mở app, trước mọi chỗ có thể mở kết nối.
    func start() {
        guard !didStart else { return }
        didStart = true
        startPathMonitor()
        guard EncryptedDNSPolicy.isEnabled else {
            state = .off
            AppLogger.shared.log("[DNS] DNS mã hoá đang tắt — dùng DNS của nhà mạng")
            return
        }
        let resolver = EncryptedDNSPolicy.resolver
        if EncryptedDNSPolicy.lastProbeFailed {
            AppLogger.shared.log("[DNS] Lần trước đã lùi về DNS thường — dò \(resolver.shortTitle) trước rồi mới bật")
        } else {
            apply(resolver)
        }
        scheduleProbe(resolver: resolver, delay: 0, reason: "mở app")
    }

    /// Màn Mạng & DNS đổi công tắc / máy chủ. Bật ⇒ áp ngay rồi dò (người dùng đang nhìn kết quả).
    func applySettings() {
        probeTask?.cancel()
        guard EncryptedDNSPolicy.isEnabled else {
            apply(nil)
            state = .off
            AppLogger.shared.log("[DNS] Tắt DNS mã hoá — dùng DNS của nhà mạng")
            return
        }
        let resolver = EncryptedDNSPolicy.resolver
        apply(resolver)
        scheduleProbe(resolver: resolver, delay: 0, reason: "đổi cài đặt")
    }

    /// Nút "Kiểm tra lại".
    func recheck() {
        guard EncryptedDNSPolicy.isEnabled else { return }
        scheduleProbe(resolver: EncryptedDNSPolicy.resolver, delay: 0, reason: "kiểm tra tay")
    }

    // MARK: - Dò

    private func scheduleProbe(resolver: EncryptedDNSResolver, delay: UInt64, reason: String) {
        probeTask?.cancel()
        guard hasNetwork else {
            state = .waitingForNetwork(resolver)
            return
        }
        state = .checking(resolver)
        probeTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }
            }
            let outcome = await EncryptedDNSProbe.run(resolver: resolver)
            guard !Task.isCancelled else { return }
            self?.handle(outcome, resolver: resolver, reason: reason)
        }
    }

    private func handle(_ outcome: EncryptedDNSProbe.Outcome, resolver: EncryptedDNSResolver, reason: String) {
        // Cài đặt đã đổi trong lúc dò ⇒ kết quả này không còn đúng chỗ.
        guard EncryptedDNSPolicy.isEnabled, EncryptedDNSPolicy.resolver == resolver else { return }
        switch outcome {
        case .reachable:
            EncryptedDNSPolicy.lastProbeFailed = false
            apply(resolver)
            state = .reachable(resolver)
            AppLogger.shared.log("[DNS] Máy chủ \(resolver.shortTitle) tới được (\(reason))")
        case .failed(let why):
            guard hasNetwork else {
                state = .waitingForNetwork(resolver)
                return
            }
            EncryptedDNSPolicy.lastProbeFailed = true
            apply(nil)
            state = .fallback(resolver, reason: why)
            AppLogger.shared.log("❌ [DNS] Không tới được máy chủ \(resolver.shortTitle) (\(reason)): \(why) — lùi về DNS thường")
        }
    }

    // MARK: - Context mặc định

    private func apply(_ resolver: EncryptedDNSResolver?) {
        guard resolver != appliedResolver else { return }
        appliedResolver = resolver
        if let resolver {
            NWParameters.PrivacyContext.default.requireEncryptedNameResolution(
                true,
                fallbackResolver: resolver.resolverConfiguration
            )
            AppLogger.shared.log("[DNS] Bắt buộc DNS mã hoá qua \(resolver.shortTitle)")
        } else {
            NWParameters.PrivacyContext.default.requireEncryptedNameResolution(false, fallbackResolver: nil)
            AppLogger.shared.log("[DNS] Về DNS thường")
        }
    }

    // MARK: - Đường mạng

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            let signature = path.availableInterfaces.map(\.name).joined(separator: ",")
            Task { @MainActor in
                EncryptedDNSRepository.shared.handlePathUpdate(satisfied: satisfied, signature: signature)
            }
        }
        monitor.start(queue: DispatchQueue(label: "TangCongCac.EncryptedDNSPath"))
        pathMonitor = monitor
    }

    private func handlePathUpdate(satisfied: Bool, signature: String) {
        let previousSignature = pathSignature
        let hadNetwork = hasNetwork
        hasNetwork = satisfied
        pathSignature = signature
        guard EncryptedDNSPolicy.isEnabled else { return }
        let resolver = EncryptedDNSPolicy.resolver
        guard satisfied else {
            probeTask?.cancel()
            state = .waitingForNetwork(resolver)
            return
        }
        // Cập nhật đầu tiên chỉ báo đường hiện tại — `start()` đã dò rồi, trừ khi lúc đó máy chưa có mạng.
        if previousSignature == nil && hadNetwork { return }
        if !hadNetwork || previousSignature != signature {
            scheduleProbe(resolver: resolver, delay: Self.pathChangeProbeDelay, reason: "đổi đường mạng")
        }
    }
}
