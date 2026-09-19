import Foundation

/// The acoustic families a physical key can belong to.
///
/// A category decides which sample pool a keypress draws from. It is
/// deliberately coarse: the app never needs to know *which* letter was typed,
/// only how big and heavy the key under the finger is.
public enum KeyCategory: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case standard
    case space
    case enter
    case backspace
    case tab
    case modifier

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Letters & Numbers"
        case .space: return "Spacebar"
        case .enter: return "Return"
        case .backspace: return "Delete"
        case .tab: return "Tab"
        case .modifier: return "Modifiers"
        }
    }

    public var summary: String {
        switch self {
        case .standard: return "Every ordinary key"
        case .space: return "Deeper, stabilised"
        case .enter: return "Heavier mechanical body"
        case .backspace: return "Slightly deeper"
        case .tab: return "Normal, a touch deeper"
        case .modifier: return "Shift, Control, Option, Command"
        }
    }

    public var symbolName: String {
        switch self {
        case .standard: return "character"
        case .space: return "space"
        case .enter: return "return"
        case .backspace: return "delete.left"
        case .tab: return "arrow.right.to.line"
        case .modifier: return "shift"
        }
    }
}

/// Lets `[KeyCategory: T]` encode as a real JSON object rather than a flat
/// key/value array.
extension KeyCategory: CodingKeyRepresentable {
    public var codingKey: CodingKey { StringCodingKey(rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}

struct StringCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
