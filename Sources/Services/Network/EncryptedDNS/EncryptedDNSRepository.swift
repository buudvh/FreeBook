import Foundation
import Network
import Observation

/// Nguồn sự thật **duy nhất** của DNS mã hoá trong app: giữ trạng thái cho màn Mạng & DNS, áp công tắc chung lên
/// `NWParameters.PrivacyContext.default`, và cập nhật `EncryptedDNSRouting` cho proxy nội bộ của các nguồn bật cờ riêng.
///
/// - **Cần DNS mã hoá** ⇔ công tắc "Bật cho cả app" (`EncryptedDNSPolicy`, mặc định tắt từ 1.3.828) **hoặc** có tiện
///   ích / nguồn Legado bật `Extension.encryptedDNSEnabled` (1.3.831). Không ai cần ⇒ không dò, không đụng gì.
/// - **Công tắc chung** áp context mặc định ⇒ mọi kết nối trong tiến trình (`URLSession`: fetch, Legado, ảnh…). WebView
///   (tiến trình WebKit) và AVPlayer không ăn ⇒ Cài đặt hướng dẫn đổi DNS cả máy.
/// - **Cờ riêng** đi qua proxy nội bộ `EncryptedDNSRelay` (`EncryptedDNSSessionRouter` chọn session); có nguồn bật cờ
///   ⇒ khởi động proxy ngay, để request đầu tiên sau khi mở app không âm thầm đi đường thường.
/// - **Mở app** (`start`, gọi ở `FreeBookApp.init` sau khi nạp bảng tiện ích): bật máy chủ **ngay** (lạc quan) rồi dò
///   (`EncryptedDNSProbe`). Ngoại lệ: lần trước kết thúc ở trạng thái lùi (`EncryptedDNSPolicy.lastProbeFailed`) ⇒
///   khởi động bằng DNS thường, dò xong mới bật.
/// - **Dò lỗi** ⇒ lùi về DNS thường (cả công tắc chung lẫn proxy), log `❌ [DNS]`. Dò lại khi đổi đường mạng (Wi-Fi ↔
///   4G, bật VPN), đổi cài đặt / cờ nguồn, bấm "Kiểm tra lại". Mất mạng không lùi — chờ có mạng rồi dò.
/// - Đổi context mặc định giữa chừng (lùi / tắt) Apple không ghi rõ có tác dụng với kết nối mới hay không — kiểm trên máy.
@MainActor
@Observable
final class EncryptedDNSRepository {
    static let shared = EncryptedDNSRepository()

    /// Giãn trước khi dò lại sau khi đổi đường mạng (đường mới thường chưa ổn định ngay).
    private static let pathChangeProbeDelay: UInt64 = 2_000_000_000

    private(set) var state: EncryptedDNSState = .off
    /// Số tiện ích / nguồn Legado đang bật DNS riêng (dòng "Bật riêng" của màn Mạng & DNS).
    private(set) var enabledSourceCount = 0

    /// Máy chủ mà context mặc định đang bắt buộc (chỉ khi công tắc chung bật); `nil` = DNS thường.
    @ObservationIgnored private var appliedResolver: EncryptedDNSResolver? = nil
    @ObservationIgnored private var probeTask: Task<Void, Never>? = nil
    @ObservationIgnored private var pathMonitor: NWPathMonitor? = nil
    /// Tên các giao diện mạng của đường hiện tại; `nil` = chưa nhận cập nhật đầu tiên của `NWPathMonitor`.
    @ObservationIgnored private var pathSignature: String? = nil
    @ObservationIgnored private var hasNetwork = true
    @ObservationIgnored private var didStart = false

    private init() {}

    /// Có ai cần DNS mã hoá không (công tắc chung hoặc cờ riêng).
    var isNeeded: Bool { EncryptedDNSPolicy.isEnabled || enabledSourceCount > 0 }

    /// Gọi một lần lúc mở app, sau khi nạp bảng tiện ích và trước mọi chỗ có thể mở kết nối.
    func start() {
        guard !didStart else { return }
        didStart = true
        startPathMonitor()
        refresh(reason: "mở app", isLaunch: true)
    }

    /// Màn Mạng & DNS đổi công tắc chung / máy chủ.
    func applySettings() {
        refresh(reason: "đổi cài đặt", isLaunch: false)
    }

    /// Một nguồn vừa bật / tắt cờ riêng.
    func sourcesDidChange() {
        refresh(reason: "đổi nguồn bật DNS riêng", isLaunch: false)
    }

    /// Mở màn Mạng & DNS: đếm lại (tiện ích có cờ có thể vừa bị gỡ) — chỉ làm mới khi số đổi.
    func refreshSourceCount() {
        guard Self.countEnabledSources() != enabledSourceCount else { return }
        sourcesDidChange()
    }

    /// Nút "Kiểm tra lại".
    func recheck() {
        guard isNeeded else { return }
        scheduleProbe(resolver: EncryptedDNSPolicy.resolver, delay: 0, reason: "kiểm tra tay")
    }

    // MARK: - Làm mới

    private func refresh(reason: String, isLaunch: Bool) {
        probeTask?.cancel()
        enabledSourceCount = Self.countEnabledSources()
        guard isNeeded else {
            route(nil)
            EncryptedDNSRelay.shared.stop()
            state = .off
            AppLogger.shared.log("[DNS] DNS mã hoá đang tắt (\(reason)) — dùng DNS của nhà mạng")
            return
        }
        if enabledSourceCount > 0 {
            EncryptedDNSRelay.shared.start()
        } else {
            EncryptedDNSRelay.shared.stop()
        }
        let resolver = EncryptedDNSPolicy.resolver
        if isLaunch && EncryptedDNSPolicy.lastProbeFailed {
            route(nil)
            AppLogger.shared.log("[DNS] Lần trước đã lùi về DNS thường — dò \(resolver.shortTitle) trước rồi mới bật")
        } else {
            route(resolver)
        }
        scheduleProbe(resolver: resolver, delay: 0, reason: reason)
    }

    /// Đặt máy chủ đang dùng (`nil` = DNS thường) cho công tắc chung (context mặc định) + proxy nội bộ.
    private func route(_ resolver: EncryptedDNSResolver?) {
        apply(EncryptedDNSPolicy.isEnabled ? resolver : nil)
        EncryptedDNSRouting.update(EncryptedDNSRouting.Snapshot(
            activeResolver: resolver,
            isGlobalApplied: appliedResolver != nil,
            hasEnabledSources: enabledSourceCount > 0
        ))
    }

    private static func countEnabledSources() -> Int {
        ExtensionLibraryRepository.installedSnapshot().reduce(0) { $0 + ($1.encryptedDNSEnabled == true ? 1 : 0) }
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
        guard isNeeded, EncryptedDNSPolicy.resolver == resolver else { return }
        switch outcome {
        case .reachable:
            EncryptedDNSPolicy.lastProbeFailed = false
            route(resolver)
            state = .reachable(resolver)
            AppLogger.shared.log("[DNS] Máy chủ \(resolver.shortTitle) tới được (\(reason))")
        case .failed(let why):
            guard hasNetwork else {
                state = .waitingForNetwork(resolver)
                return
            }
            EncryptedDNSPolicy.lastProbeFailed = true
            route(nil)
            state = .fallback(resolver, reason: why)
            AppLogger.shared.log("❌ [DNS] Không tới được máy chủ \(resolver.shortTitle) (\(reason)): \(why) — lùi về DNS thường")
        }
    }

    // MARK: - Context mặc định (chỉ công tắc chung)

    private func apply(_ resolver: EncryptedDNSResolver?) {
        guard resolver != appliedResolver else { return }
        appliedResolver = resolver
        if let resolver {
            NWParameters.PrivacyContext.default.requireEncryptedNameResolution(
                true,
                fallbackResolver: resolver.resolverConfiguration
            )
            AppLogger.shared.log("[DNS] Cả app: bắt buộc DNS mã hoá qua \(resolver.shortTitle)")
        } else {
            NWParameters.PrivacyContext.default.requireEncryptedNameResolution(false, fallbackResolver: nil)
            AppLogger.shared.log("[DNS] Cả app: về DNS thường")
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
        guard isNeeded else { return }
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
