import Foundation

enum RequestCategory: Sendable {
    case general
    case search
    case stream
}

/// A conservative client-side limiter. SoundCloud documents roughly 100 general
/// requests per minute, 3,000 searches per hour and 1,500 stream requests per 24h.
/// We keep headroom for retries and multiple screens.
actor RateLimiter {
    private struct Rule {
        let limit: Int
        let window: TimeInterval
    }

    private let rules: [RequestCategory: Rule] = [
        .general: Rule(limit: 80, window: 60),
        .search: Rule(limit: 2_400, window: 3_600),
        .stream: Rule(limit: 1_200, window: 86_400)
    ]

    private var hits: [RequestCategory: [Date]] = [:]

    func acquire(_ category: RequestCategory) async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            prune(now: now)

            let generalRule = rules[.general]!
            let generalOK = (hits[.general]?.count ?? 0) < generalRule.limit

            var categoryOK = true
            var categoryWait: TimeInterval = 0
            if category != .general, let rule = rules[category] {
                let categoryHits = hits[category] ?? []
                categoryOK = categoryHits.count < rule.limit
                if !categoryOK, let oldest = categoryHits.first {
                    categoryWait = max(0, oldest.addingTimeInterval(rule.window).timeIntervalSince(now))
                }
            }

            let generalWait: TimeInterval
            if generalOK {
                generalWait = 0
            } else if let oldest = hits[.general]?.first {
                generalWait = max(0, oldest.addingTimeInterval(generalRule.window).timeIntervalSince(now))
            } else {
                generalWait = 1
            }

            if generalOK && categoryOK {
                hits[.general, default: []].append(now)
                if category != .general {
                    hits[category, default: []].append(now)
                }
                return
            }

            let wait = max(generalWait, categoryWait, 0.25)
            let nanoseconds = UInt64(min(wait, 60) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    private func prune(now: Date) {
        for (category, rule) in rules {
            guard var values = hits[category] else { continue }
            values.removeAll { now.timeIntervalSince($0) >= rule.window }
            hits[category] = values
        }
    }
}
