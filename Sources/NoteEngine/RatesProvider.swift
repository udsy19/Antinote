import Foundation
import Combine
import JotterCore

/// Exchange rates as units per 1 USD (e.g. EUR 0.92, BTC 0.0000105).
public struct ExchangeRates: Sendable {
    public var perUSD: [String: Double]
    /// Changes whenever the rates change; part of the analysis cache key.
    public var version: Int

    public init(perUSD: [String: Double], version: Int = 0) {
        self.perUSD = perUSD; self.version = version
    }

    /// USD value of one unit of `code`, or nil when no rate is known.
    public func usdPerUnit(_ code: String) -> Double? {
        if code == "USD" { return 1 }
        guard let rate = perUSD[code], rate > 0 else { return nil }
        return 1 / rate
    }
}

/// Fetches fiat (open.er-api.com) and crypto (CoinGecko) rates when Settings → Privacy allows it, caches them in
/// Application Support, refreshes daily when "Update currency rates daily" is on, and applies custom rates on top.
public final class RatesProvider: @unchecked Sendable {
    public static let shared = RatesProvider()
    /// Posted on the main queue when rates (fetched or custom) change.
    public static let didUpdate = Notification.Name("JotterExchangeRatesDidUpdate")

    private let lock = NSLock()
    private var fetched: [String: Double] = [:]
    private var fetchedVersion = 0
    private var fetching = false
    public private(set) var lastUpdated: Date?
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    private let cacheURL: URL

    init(cacheURL: URL = JotterPaths.support.appendingPathComponent("exchange-rates.json")) {
        self.cacheURL = cacheURL
    }

    /// Fetched rates with `Defaults[.customRates]` applied.
    public var current: ExchangeRates {
        let custom = Defaults[.customRates]
        lock.lock(); defer { lock.unlock() }
        var rates = fetched
        for (code, rate) in custom where rate > 0 { rates[code.uppercased()] = rate }
        var hasher = Hasher()
        hasher.combine(fetchedVersion)
        for (code, rate) in custom.sorted(by: { $0.key < $1.key }) { hasher.combine(code); hasher.combine(rate) }
        return ExchangeRates(perUSD: rates, version: hasher.finalize())
    }

    /// Loads the cache, refreshes when due, and keeps checking hourly. Call once at launch.
    public func start() {
        loadCache()
        refreshIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.refreshIfNeeded() }
        settingsObserver = Defaults.changes
            .filter { $0 == Defaults.Keys.customRates.name || $0 == Defaults.Keys.allowCurrencyRates.name }
            .sink { [weak self] name in
                if name == Defaults.Keys.allowCurrencyRates.name { self?.refreshIfNeeded() }
                Self.postUpdate()
            }
    }

    public func refreshIfNeeded() {
        lock.lock()
        let empty = fetched.isEmpty
        let stale = lastUpdated.map { Date().timeIntervalSince($0) > 86_400 } ?? true
        lock.unlock()
        if empty || (stale && Defaults[.autoUpdateRates]) { refresh() }
    }

    /// Fetches fresh rates now (no-op when blocked in Settings → Privacy).
    public func refresh(completion: ((Bool) -> Void)? = nil) {
        guard Defaults[.allowCurrencyRates] else {
            Log.app.info("Fetching currency rates blocked by user preferences")
            completion?(false); return
        }
        lock.lock()
        if fetching { lock.unlock(); completion?(false); return }
        fetching = true
        lock.unlock()

        let group = DispatchGroup()
        var fiat: [String: Double] = [:]
        var crypto: [String: Double] = [:]
        group.enter()
        fetchJSON("https://open.er-api.com/v6/latest/USD") { json in
            if let rates = json?["rates"] as? [String: Any] {
                for (code, value) in rates { if let v = (value as? NSNumber)?.doubleValue { fiat[code] = v } }
            }
            group.leave()
        }
        group.enter()
        let ids = CurrencyCatalog.crypto.values.sorted().joined(separator: ",")
        fetchJSON("https://api.coingecko.com/api/v3/simple/price?ids=\(ids)&vs_currencies=usd") { json in
            for (code, id) in CurrencyCatalog.crypto {
                if let price = ((json?[id] as? [String: Any])?["usd"] as? NSNumber)?.doubleValue, price > 0 {
                    crypto[code] = 1 / price
                }
            }
            group.leave()
        }
        group.notify(queue: .main) { [self] in
            let merged = fiat.merging(crypto) { a, _ in a }
            lock.lock()
            fetching = false
            let ok = !merged.isEmpty
            if ok {
                fetched.merge(merged) { _, new in new }
                fetchedVersion += 1
                lastUpdated = Date()
            }
            let snapshot = fetched, date = lastUpdated
            lock.unlock()
            if ok {
                saveCache(snapshot, date: date ?? Date())
                Self.postUpdate()
            } else {
                Log.app.error("Failed to fetch latest currency rates. Using saved rates with manual overrides.")
            }
            completion?(ok)
        }
    }

    private static func postUpdate() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: didUpdate, object: nil) }
    }

    private func fetchJSON(_ address: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: address) else { completion(nil); return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            completion(data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }.resume()
    }

    private struct Cache: Codable {
        var updated: Date
        var rates: [String: Double]
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        lock.lock()
        fetched = cache.rates
        lastUpdated = cache.updated
        fetchedVersion += 1
        lock.unlock()
    }

    private func saveCache(_ rates: [String: Double], date: Date) {
        guard let data = try? JSONEncoder().encode(Cache(updated: date, rates: rates)) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
