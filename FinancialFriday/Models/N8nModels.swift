import Foundation

// DTOs for the two n8n workflows.
//
// n8n is an AI pipeline we do not control: keys can come back as "estimatedSpend",
// "estimated_spend" or "Estimated Spend", numbers can arrive as strings ("£120.50"),
// and booleans as "Yes"/"No". Every row is therefore decoded generically and then
// mapped through tolerant helpers instead of relying on a fixed JSON schema.

// MARK: - Raw JSON

enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): value ? "Yes" : "No"
        case .null: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Self.parseNumber(value)
        case .bool(let value): value ? 1 : 0
        case .null: nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .number(let value): value != 0
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespaces).lowercased() {
            case "yes", "y", "true", "1": true
            case "no", "n", "false", "0", "": false
            default: nil
            }
        case .null: nil
        }
    }

    private static func parseNumber(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(
            of: #"[^0-9.,-]"#,
            with: "",
            options: .regularExpression
        )
        if cleaned.isEmpty { return nil }
        // "1.234,56" (European) vs "1,234.56" (British)
        let normalised: String
        if cleaned.contains(",") && cleaned.contains(".") {
            let decimalIsComma = cleaned.lastIndex(of: ",")! > cleaned.lastIndex(of: ".")!
            normalised = decimalIsComma
                ? cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                : cleaned.replacingOccurrences(of: ",", with: "")
        } else if cleaned.contains(",") {
            normalised = cleaned.replacingOccurrences(of: ",", with: ".")
        } else {
            normalised = cleaned
        }
        return Double(normalised)
    }
}

/// One decoded row with normalised keys (lowercase, alphanumerics only).
struct FlexibleRow: Decodable, Sendable {
    let values: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
        // A duplicate after normalisation (e.g. "price" and "Price") must not trap.
        var normalised: [String: JSONValue] = [:]
        for (key, value) in raw {
            normalised[Self.normalise(key)] = value
        }
        values = normalised
    }

    init(values: [String: JSONValue]) {
        self.values = values
    }

    static func normalise(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func string(_ key: String) -> String? {
        values[Self.normalise(key)]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func double(_ key: String) -> Double? { values[Self.normalise(key)]?.doubleValue }
    func bool(_ key: String) -> Bool? { values[Self.normalise(key)]?.boolValue }
}

// MARK: - Envelope

/// Accepts `{ "ok": true, "rows": [...], "meta": {...} }` and a bare `[...]`.
struct N8nEnvelope: Decodable, Sendable {
    let ok: Bool
    let rows: [FlexibleRow]
    let meta: [String: JSONValue]
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case ok, rows, data, meta, error
    }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([FlexibleRow].self) {
            ok = true
            rows = array
            meta = [:]
            error = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? container.decode(Bool.self, forKey: .ok)) ?? true
        rows = (try? container.decode([FlexibleRow].self, forKey: .rows))
            ?? (try? container.decode([FlexibleRow].self, forKey: .data))
            ?? []
        meta = Dictionary(
            ((try? container.decode([String: JSONValue].self, forKey: .meta)) ?? [:])
                .map { (Self.normaliseMetaKey($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        error = try? container.decode(String.self, forKey: .error)
    }

    func metaString(_ key: String) -> String? {
        meta[Self.normaliseMetaKey(key)]?.stringValue
    }

    func metaInt(_ key: String) -> Int? {
        meta[Self.normaliseMetaKey(key)]?.doubleValue.map(Int.init)
    }

    private static func normaliseMetaKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Calendar Spending Analysis

enum SpendingLevel: String, Sendable, CaseIterable {
    case low, medium, high

    init(raw: String?) {
        switch raw?.lowercased() {
        case "high", "very high": self = .high
        case "medium", "med", "moderate": self = .medium
        default: self = .low
        }
    }

    var label: String { rawValue.capitalized }
}

enum Confidence: String, Sendable {
    case low, medium, high

    init(raw: String?) {
        switch raw?.lowercased() {
        case "high": self = .high
        case "medium", "med": self = .medium
        default: self = .low
        }
    }
}

struct CalendarOccasion: Identifiable, Sendable, Hashable {
    let date: Date
    let title: String
    let type: String
    let level: SpendingLevel
    let bigSpending: Bool
    let estimatedSpend: Double
    let costDrivers: String
    let confidence: Confidence
    let tip: String

    var id: String { "\(date.timeIntervalSince1970)-\(title)-\(estimatedSpend)" }

    init(date: Date, title: String, type: String, level: SpendingLevel, bigSpending: Bool,
         estimatedSpend: Double, costDrivers: String, confidence: Confidence, tip: String) {
        self.date = date
        self.title = title
        self.type = type
        self.level = level
        self.bigSpending = bigSpending
        self.estimatedSpend = estimatedSpend
        self.costDrivers = costDrivers
        self.confidence = confidence
        self.tip = tip
    }

    init?(row: FlexibleRow) {
        guard let title = row.string("title") ?? row.string("event") ?? row.string("name"),
              let date = Self.parseDate(row.string("date") ?? row.string("start")) else { return nil }
        self.date = date
        self.title = title
        self.type = row.string("type") ?? row.string("category") ?? "Event"
        self.level = SpendingLevel(raw: row.string("spendingLevel") ?? row.string("level"))
        self.bigSpending = row.bool("bigSpending") ?? false
        self.estimatedSpend = row.double("estimatedSpendValue")
            ?? row.double("estimated_spend_value")
            ?? row.double("estimatedSpend")
            ?? row.double("estimate")
            ?? 0
        self.costDrivers = row.string("costDrivers") ?? row.string("drivers") ?? ""
        self.confidence = Confidence(raw: row.string("confidence"))
        self.tip = row.string("tip") ?? row.string("advice") ?? ""
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let formats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd",
                       "dd/MM/yyyy", "dd/MM/yyyy HH:mm"]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "Europe/London")
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: raw) { return date }
        }
        return nil
    }
}

// MARK: - Product Image Price Finder

enum PriceMatchKind: String, Sendable {
    case exact
    case sameBrand
    case similar

    init(raw: String?) {
        switch raw?.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-") {
        case "exact", "exact-match", "cheapest": self = .exact
        case "same-brand", "samebrand", "same": self = .sameBrand
        default: self = .similar
        }
    }

    var label: String {
        switch self {
        case .exact: "Cheapest match"
        case .sameBrand: "Same manufacturer"
        case .similar: "Similar product"
        }
    }
}

struct PriceMatch: Identifiable, Sendable, Hashable {
    let kind: PriceMatchKind
    let title: String
    let manufacturer: String
    let model: String
    let shop: String
    let price: Double
    let currency: String
    let link: URL?
    let notes: String

    var id: String { "\(kind.rawValue)-\(shop)-\(price)" }

    init(kind: PriceMatchKind, title: String, manufacturer: String, model: String, shop: String,
         price: Double, currency: String, link: URL?, notes: String) {
        self.kind = kind
        self.title = title
        self.manufacturer = manufacturer
        self.model = model
        self.shop = shop
        self.price = price
        self.currency = currency
        self.link = link
        self.notes = notes
    }

    init?(row: FlexibleRow) {
        guard let shop = row.string("shop") ?? row.string("store") ?? row.string("merchant"),
              let price = row.double("price") else { return nil }
        self.kind = PriceMatchKind(raw: row.string("kind") ?? row.string("type"))
        self.title = row.string("title") ?? row.string("name") ?? ""
        self.manufacturer = row.string("manufacturer") ?? row.string("brand") ?? ""
        self.model = row.string("model") ?? ""
        self.shop = shop
        self.price = price
        self.currency = row.string("currency") ?? "GBP"
        self.link = (row.string("link") ?? row.string("url")).flatMap(URL.init(string:))
        self.notes = row.string("notes") ?? row.string("note") ?? ""
    }
}

// MARK: - Responses

struct CalendarSpendResult: Sendable {
    let occasions: [CalendarOccasion]
    let daysAhead: Int
    let currency: String
    let ignoredCount: Int?
    let isDemo: Bool
}

struct PriceFinderResult: Sendable {
    let matches: [PriceMatch]
    let product: String?
    let isDemo: Bool
}
