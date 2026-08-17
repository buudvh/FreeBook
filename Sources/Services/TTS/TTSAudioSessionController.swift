public func configureAudioSession() -> Bool {
    let session = AVAudioSession.sharedInstance()

    do {
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: []
        )

        AppLogger.shared.log(
            "✅ [TTSAudioSessionController] setCategory OK"
        )
    } catch {
        let e = error as NSError

        AppLogger.shared.log(
            "❌ [TTSAudioSessionController] setCategory failed " +
            "domain=\(e.domain), code=\(e.code), error=\(error)"
        )

        return false
    }

    do {
        try session.setActive(true)

        AppLogger.shared.log(
            "✅ [TTSAudioSessionController] setActive OK"
        )

        return true
    } catch {
        let e = error as NSError

        AppLogger.shared.log(
            "❌ [TTSAudioSessionController] setActive failed " +
            "domain=\(e.domain), code=\(e.code), error=\(error)"
        )

        return false
    }
}