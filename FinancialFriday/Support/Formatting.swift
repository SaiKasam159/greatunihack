import Foundation

enum AppFormatting {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GBP"
        formatter.locale = Locale(identifier: "en_GB")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func currency(_ value: Decimal) -> String {
        currency.string(from: NSDecimalNumber(decimal: value)) ?? "£0.00"
    }

    static func compactCurrency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        if abs(number) >= 1_000 { return String(format: "£%.1fk", number / 1_000) }
        return String(format: "£%.0f", number)
    }

    static func decimal(from text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: "£", with: "").replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
