import Foundation

/// Everything the app needs to reach the two published n8n webhooks.
///
/// Override `N8nBaseURL` in UserDefaults (or a scheme environment variable read at
/// launch) to point the app at a tunnel or a self-hosted instance without editing code.
struct N8nConfiguration: Sendable {
    var baseURL: URL
    var calendarPath: String
    var pricePath: String
    var timeout: TimeInterval

    static let `default` = N8nConfiguration(
        baseURL: URL(string: UserDefaults.standard.string(forKey: "N8nBaseURL")
                      ?? "https://shalev787.app.n8n.cloud")!,
        calendarPath: "/webhook/calendar-spend",
        pricePath: "/webhook/product-price",
        timeout: 45
    )
}

enum N8nError: LocalizedError {
    case notPublished
    case invalidURL
    case rejected(String)
    case http(status: Int, message: String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notPublished:
            "The n8n workflow is not published yet."
        case .invalidURL:
            "The n8n URL is not configured correctly."
        case .rejected(let message):
            message
        case .http(let status, let message):
            "n8n returned HTTP \(status)\(message.isEmpty ? "" : ": \(message)")"
        case .transport(let message):
            "Could not reach n8n: \(message)"
        case .decoding(let message):
            "Unexpected response from n8n: \(message)"
        }
    }
}

struct N8nClient: Sendable {
    let configuration: N8nConfiguration
    private let session: URLSession

    init(configuration: N8nConfiguration = .default, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - Workflow 2: Calendar Spending Analysis

    func calendarSpend(daysAhead: Int = 90, currency: String = "GBP") async throws -> CalendarSpendResult {
        let envelope = try await post(
            configuration.calendarPath,
            body: CalendarRequest(daysAhead: daysAhead, currency: currency)
        )
        let occasions = envelope.rows
            .compactMap(CalendarOccasion.init(row:))
            .sorted { $0.date < $1.date }

        return CalendarSpendResult(
            occasions: occasions,
            daysAhead: envelope.metaInt("daysAhead") ?? daysAhead,
            currency: envelope.metaString("currency") ?? currency,
            ignoredCount: envelope.metaInt("ignored"),
            isDemo: false
        )
    }

    // MARK: - Workflow 1: Product Image Price Finder

    func priceFinder(base64Image: String, country: String = "uk") async throws -> PriceFinderResult {
        // Keep well under the workflow's 4 MB guard for the decoded image.
        guard base64Image.count < 5_400_000 else {
            throw N8nError.rejected("That photo is over 4 MB even after compression. Try a smaller one.")
        }
        let envelope = try await post(
            configuration.pricePath,
            body: PriceRequest(image: base64Image, country: country)
        )
        let matches = envelope.rows.compactMap(PriceMatch.init(row:))
        return PriceFinderResult(
            matches: matches,
            product: envelope.metaString("product"),
            isDemo: false
        )
    }

    // MARK: - Transport

    private struct CalendarRequest: Encodable, Sendable {
        let daysAhead: Int
        let currency: String
    }

    private struct PriceRequest: Encodable, Sendable {
        let image: String
        let country: String
    }

    private func post<Body: Encodable & Sendable>(_ path: String, body: Body) async throws -> N8nEnvelope {
        guard let url = URL(string: path, relativeTo: configuration.baseURL) else {
            throw N8nError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.timeout
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw N8nError.transport("No HTTP response")
        }

        // A draft workflow answers 404 "webhook not registered" until it is published.
        if http.statusCode == 404 {
            throw N8nError.notPublished
        }

        let envelope = try? JSONDecoder().decode(N8nEnvelope.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            let message = envelope?.error ?? String(data: data, encoding: .utf8) ?? ""
            throw N8nError.http(status: http.statusCode, message: String(message.prefix(220)))
        }
        guard let envelope else {
            throw N8nError.decoding("The body was not valid JSON.")
        }
        guard envelope.ok else {
            throw N8nError.rejected(envelope.error ?? "The workflow returned ok: false.")
        }
        return envelope
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost]
            .contains(error.code) {
            try? await Task.sleep(for: .milliseconds(400))
            do {
                return try await session.data(for: request)
            } catch {
                throw N8nError.transport(error.localizedDescription)
            }
        } catch {
            throw N8nError.transport(error.localizedDescription)
        }
    }
}
