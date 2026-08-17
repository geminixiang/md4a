import Foundation

/// User-controlled onboarding state. The system integration remains behind a
/// protocol so decisions can be tested without changing Launch Services.
enum MarkdownDefaultAppDecision: String, Equatable {
    case notAsked
    case dismissed
    case requested
}

struct MarkdownDefaultAppOnboarding {
    private(set) var decision: MarkdownDefaultAppDecision

    var shouldOfferInWelcome: Bool { decision == .notAsked }

    mutating func dismiss() {
        decision = .dismissed
    }

    mutating func confirmRequest() {
        decision = .requested
    }

    mutating func resetForSettings() {
        decision = .notAsked
    }
}

@MainActor
protocol MarkdownDefaultApplicationService {
    func isCurrentApplicationDefault() -> Bool
    func setCurrentApplicationAsDefault() async throws
}
