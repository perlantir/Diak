import Foundation

@MainActor
public final class HermesState: ObservableObject {
    @Published public var daemon: DaemonStatus
    @Published public var sessions: [HermesSession]
    @Published public var messages: [HermesMessage]
    @Published public var approvals: [HermesApprovalRequest]
    @Published public var evidence: [HermesActionEvidence]
    @Published public var skills: [HermesSkill]
    @Published public var connectors: [HermesConnector]
    @Published public var automations: [HermesAutomationJob]
    @Published public var memory: [HermesMemoryItem]
    @Published public var config: HermesConfigSnapshot?

    public init(daemon: DaemonStatus = .unknown,
                sessions: [HermesSession] = [],
                messages: [HermesMessage] = [],
                approvals: [HermesApprovalRequest] = [],
                evidence: [HermesActionEvidence] = [],
                skills: [HermesSkill] = [],
                connectors: [HermesConnector] = [],
                automations: [HermesAutomationJob] = [],
                memory: [HermesMemoryItem] = [],
                config: HermesConfigSnapshot? = nil) {
        self.daemon = daemon
        self.sessions = sessions
        self.messages = messages
        self.approvals = approvals
        self.evidence = evidence
        self.skills = skills
        self.connectors = connectors
        self.automations = automations
        self.memory = memory
        self.config = config
    }
}
