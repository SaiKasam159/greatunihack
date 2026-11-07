import Foundation

enum TransactionDataError: LocalizedError {
    case missingFile
    case unreadableFile
    case invalidHeader
    case invalidRecord(line: Int)

    var errorDescription: String? {
        switch self {
        case .missingFile: "The bundled transaction dataset could not be found."
        case .unreadableFile: "The transaction dataset could not be read."
        case .invalidHeader: "The transaction dataset has an unexpected format."
        case .invalidRecord(let line): "A transaction on line \(line) could not be parsed."
        }
    }
}

enum TransactionDataService {
    static func loadBundledTransactions() async throws -> [Transaction] {
        guard let url = Bundle.main.url(forResource: "financialfriday_synthetic_1user_1year", withExtension: "csv") else {
            throw TransactionDataError.missingFile
        }
        return try await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  var text = String(data: data, encoding: .utf8) else {
                throw TransactionDataError.unreadableFile
            }
            text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard let header = lines.first,
                  parseCSVRow(header) == ["timestamp", "merchant", "category", "amount_gbp", "type", "channel", "user_id"] else {
                throw TransactionDataError.invalidHeader
            }

            var transactions: [Transaction] = []
            transactions.reserveCapacity(lines.count - 1)
            for (offset, line) in lines.dropFirst().enumerated() {
                let fields = parseCSVRow(line)
                guard fields.count == 7,
                      let date = parseTimestamp(fields[0]),
                      let amount = Decimal(string: fields[3], locale: Locale(identifier: "en_US_POSIX")) else {
                    throw TransactionDataError.invalidRecord(line: offset + 2)
                }
                transactions.append(Transaction(
                    id: offset,
                    timestamp: date,
                    merchant: fields[1],
                    category: fields[2],
                    amount: amount,
                    type: fields[4].lowercased(),
                    channel: fields[5],
                    userID: fields[6]
                ))
            }
            return transactions.sorted { $0.timestamp < $1.timestamp }
        }.value
    }

    private nonisolated static func parseTimestamp(_ value: String) -> Date? {
        let parts = value.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let date = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].split(separator: ":").compactMap { Int($0) }
        guard date.count == 3, time.count == 2 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: date[0], month: date[1], day: date[2], hour: time[0], minute: time[1]
        ))
    }

    private nonisolated static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var index = row.startIndex
        while index < row.endIndex {
            let character = row[index]
            if character == "\"" {
                let next = row.index(after: index)
                if inQuotes, next < row.endIndex, row[next] == "\"" {
                    field.append("\"")
                    index = row.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = row.index(after: index)
        }
        fields.append(field)
        return fields
    }
}
