import Foundation

/// Read-only toggle that flips when the app is launched under the
/// XCUITest harness (`--diak-uat-mode`). The flag is the single seam
/// the production binary uses to skip onboarding and bind the in-memory
/// `MockHermesAPIClient` instead of the URLSession bridge client — no
/// production code path is altered when the flag is absent.
enum DiakUATMode {
    static let launchArgument = "--diak-uat-mode"

    /// `true` only if the current process was launched with the UAT
    /// flag. Evaluated once at first read and cached so view-model
    /// inits resolve the same value.
    static let isActive: Bool = CommandLine.arguments.contains(launchArgument)
}
