import Foundation

/// Boundary for the Diak component that owns the lifecycle of the Hermes
/// dashboard subprocess (`hermes dashboard --no-open --port … --host …`).
///
/// Implementations spawn the subprocess, scrape the ephemeral session
/// token from the SPA HTML, publish health updates, and tear the process
/// down on demand. The protocol exists so that downstream services (and
/// later UI wiring in Work Unit 6) can be written against the abstract
/// supervisor — for example, allowing unit tests to swap in a fake.
@MainActor
public protocol HermesProcessSupervising: AnyObject {
    /// Current lifecycle state. Observable via `@Published` on concrete
    /// implementations.
    var health: HermesProcessHealth { get }

    /// Start the Hermes dashboard subprocess. Resolves when the process is
    /// bound and the session token has been scraped, or throws if either
    /// of those fails before the configured startup timeout.
    func start() async throws

    /// Stop the supervised process via SIGTERM, falling back to SIGKILL
    /// if the process does not exit before the configured stop timeout.
    /// Idempotent — calling `stop()` on a stopped supervisor is a no-op.
    func stop() async

    /// Stop + start. The PID after restart differs from the PID before.
    /// The dashboard token also rotates (per Phase 0.5 REALITY.md the
    /// token is regenerated on every process start).
    func restart() async throws
}
