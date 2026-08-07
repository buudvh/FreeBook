import Foundation
import CallKit
import AVFoundation

@MainActor
public final class TTSCallObserver: NSObject, CXCallObserverDelegate, Sendable {
    private let callObserver = CXCallObserver()
    public var onCallBegan: (@Sendable () -> Void)?
    public var onCallEnded: (@Sendable () -> Void)?

    public override init() {
        super.init()
        callObserver.setDelegate(self, queue: .main)
    }

    public nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if !call.hasEnded {
                AppLogger.shared.log("📞 [TTSCallObserver] Incoming or active call detected (UUID: \(call.uuid)). Pausing TTS.")
                self.onCallBegan?()
            } else {
                AppLogger.shared.log("📞 [TTSCallObserver] Call ended (UUID: \(call.uuid)).")
                self.onCallEnded?()
            }
        }
    }
}
