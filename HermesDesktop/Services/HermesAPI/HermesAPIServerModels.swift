import Foundation

// MARK: - Naming convention
//
// The Hermes API Server is OpenAI-compatible per its own module
// docstring at `~/.hermes/hermes-agent/gateway/platforms/api_server.py`.
// Wire format is snake_case for the OpenAI parts and snake_case for
// Hermes' own /v1/runs additions. We use `convertFromSnakeCase` on the
// decoder and the camelCase form on Swift properties (e.g. `runId`,
// `finishReason`).

// MARK: - Chat completion

/// Request body for `POST /v1/chat/completions`. Strict subset of the
/// OpenAI Chat Completions API — enough for Phase 1 to round-trip a
/// "send a prompt, get a reply" exchange. Streaming variants are out of
/// scope; we keep `stream` here for callers that want to opt in later.
public struct ChatCompletionRequest: Codable, Sendable, Equatable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?
    public let stream: Bool?

    public init(model: String,
                messages: [ChatMessage],
                temperature: Double? = nil,
                maxTokens: Int? = nil,
                stream: Bool? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

/// One chat message in either the request or response. Role + content
/// is the load-bearing payload; tool fields are kept for forward-compat
/// with tool-calling models.
public struct ChatMessage: Codable, Sendable, Equatable, Hashable {
    public let role: String
    public let content: String?
    public let name: String?
    public let toolCallId: String?

    public init(role: String,
                content: String?,
                name: String? = nil,
                toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
    }
}

/// Response body for non-streaming `POST /v1/chat/completions`.
public struct ChatCompletionResponse: Codable, Sendable, Equatable {
    public let id: String
    public let model: String?
    public let choices: [ChatCompletionChoice]
    public let usage: ChatCompletionUsage?
    public let created: Int?
    public let object: String?
}

public struct ChatCompletionChoice: Codable, Sendable, Equatable {
    public let index: Int
    public let message: ChatMessage
    public let finishReason: String?
}

public struct ChatCompletionUsage: Codable, Sendable, Equatable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
}

// MARK: - Runs (Hermes-specific addition)

/// Request body for `POST /v1/runs`. The API server returns 202 + a
/// run_id immediately; the caller then subscribes to
/// `/v1/runs/{id}/events` for the SSE lifecycle stream.
public struct RunRequest: Codable, Sendable, Equatable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?

    public init(model: String,
                messages: [ChatMessage],
                temperature: Double? = nil,
                maxTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// Response body for `POST /v1/runs` — minimal "we accepted this; here's
/// your handle" envelope.
public struct RunStartResponse: Codable, Sendable, Equatable {
    public let runId: String
    public let status: String?
}

/// One Server-Sent Event from `/v1/runs/{run_id}/events`. The Hermes
/// SSE format follows the HTML5 SSE spec: each event has an optional
/// `event:` type, optional `id:`, and one or more `data:` lines whose
/// values are concatenated. The `data` value is whatever the server
/// chose to send — typically a JSON object. Diak preserves the raw
/// string so the caller can decode it into a type appropriate for the
/// specific event kind (lifecycle event vs. token chunk).
public struct RunEvent: Sendable, Equatable {
    public let event: String?
    public let id: String?
    public let data: String
}
