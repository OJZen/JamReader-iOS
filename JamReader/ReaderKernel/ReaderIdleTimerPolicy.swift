enum ReaderIdleTimerPolicy {
    static func shouldDisableIdleTimer(
        isSceneActive: Bool,
        hasDocument: Bool,
        keepsScreenAwake: Bool
    ) -> Bool {
        isSceneActive && hasDocument && keepsScreenAwake
    }
}
