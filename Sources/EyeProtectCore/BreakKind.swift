import Foundation

/// The two grades of Break issued by the Unified Timer. See CONTEXT.md.
public enum BreakKind: Equatable, Sendable {
    case eye      // short 20-20-20 look-away
    case longRest // promoted "get up and walk" break

    public var title: String {
        switch self {
        case .eye:      return "Look 20 feet away"
        case .longRest: return "Time to get up"
        }
    }

    public var subtitle: String {
        switch self {
        case .eye:      return "Rest your eyes — focus on something ~20 feet away."
        case .longRest: return "Stand up, stretch, walk a little. Your eyes and body will thank you."
        }
    }
}
