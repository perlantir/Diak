import Foundation

/// Lifecycle state of the Hermes dashboard process from Diak's perspective.
///
/// The supervisor publishes this; UI and other services consume it. Token
/// lives inside `.running` because it is bound to the dashboard process —
/// per Phase 0.5 REALITY.md, the dashboard regenerates a new token on
/// every process start. Pairing pid + port + token in one case keeps that
/// coupling explicit.
public enum HermesProcessHealth: Sendable, Equatable {
    /// Not running. No supervised process exists.
    case stopped
    /// Subprocess launched, waiting for HTTP `GET /` to return and for the
    /// session token to be scraped. Bounded by the supervisor's startup
    /// timeout.
    case starting
    /// Dashboard is up, HTTP server responding, token captured.
    case running(pid: Int32, port: Int, token: String)
    /// `stop()` was called and is awaiting graceful exit (SIGTERM, then
    /// SIGKILL fallback).
    case stopping
    /// Process exited unexpectedly (the supervisor did not request the
    /// stop). The reason string is operator-readable.
    case crashed(reason: String)
}
