/// Requests permission only for an enabled feature; never treats a request as authorization.
/// Closures keep the decision testable without touching the real Screen Recording permission.
struct ScreenCapturePermissionGate {
    let preflight: () -> Bool
    let request: () -> Bool

    func requestIfNeeded(tintingEnabled: Bool) {
        guard tintingEnabled, !preflight() else { return }
        // Capture must still independently preflight access, regardless of this result.
        _ = request()
    }
}
