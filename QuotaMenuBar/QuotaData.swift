//
//  QuotaData.swift
//  QuotaMenuBar
//
//  Data models + JSON parsing for the cache files feeding the app:
//    ~/.claude/rate_limits_cache.json        (fetch_claude_usage.py)      — Claude 5h/7d quota
//    ~/.antigravity/quota_cache.json         (fetch_antigravity_usage.py) — Gemini quota
//    ~/.quota-menubar/daily_usage_cache.json (fetch_daily_usage.py)       — per-day Claude Code tokens
//
//  Both upstreams have quietly changed their timestamp representation over
//  time (epoch number vs. ISO-8601 string), so every timestamp is decoded
//  through `LenientDate`, which accepts either.
//

import Foundation

// MARK: - Claude JSON Schema

/// Top-level structure of `~/.claude/rate_limits_cache.json`
///
/// ```json
/// {
///   "five_hour":  { "used_percentage": 7.0,  "resets_at": 1786377138 },
///   "seven_day":  { "used_percentage": 78.0, "resets_at": 1786377138 },
///   "updated_at": 1786377138
/// }
/// ```
///
/// `resets_at` is currently a Unix epoch (claude.ai's usage endpoint), but
/// older captures were ISO-8601 strings, so it is decoded via `LenientDate`.
struct ClaudeRawCache: Decodable {
    let fiveHour: ClaudeWindow
    let sevenDay: ClaudeWindow
    let updatedAt: Double  // Unix timestamp

    enum CodingKeys: String, CodingKey {
        case fiveHour  = "five_hour"
        case sevenDay  = "seven_day"
        case updatedAt = "updated_at"
    }
}

struct ClaudeWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: LenientDate?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt       = "resets_at"
    }
}

// MARK: - Gemini JSON Schema

/// Top-level structure of `~/.antigravity/quota_cache.json`, as written by
/// `~/.antigravity/fetch_antigravity_usage.py`:
///
/// ```json
/// {
///   "label": "Gemini 3.1 Pro (High)",
///   "remaining_percentage": 99.0,
///   "resets_at": "2026-08-29T06:13:10Z",
///   "updated_at": 1787972095
/// }
/// ```
struct GeminiRawCache: Decodable {
    let label: String
    let remainingPercentage: Double
    let resetsAt: LenientDate?
    let updatedAt: LenientDate?

    enum CodingKeys: String, CodingKey {
        case label
        case remainingPercentage = "remaining_percentage"
        case resetsAt            = "resets_at"
        case updatedAt           = "updated_at"
    }
}

// MARK: - Daily Usage JSON Schema

/// Top-level structure of `~/.quota-menubar/daily_usage_cache.json`, written by
/// `~/.quota-menubar/fetch_daily_usage.py` (a wrapper around `ccusage daily`).
/// Always exactly 7 entries, oldest first, last entry = today; days with no
/// activity are present with zeros. Claude Code CLI usage on this Mac only.
///
/// ```json
/// {
///   "updated_at": 1787974520,
///   "days": [
///     { "date": "2026-08-29", "total_tokens": 27603168, "input_tokens": 290,
///       "output_tokens": 142555, "cache_creation_tokens": 903954,
///       "cache_read_tokens": 26556369, "cost": 10.3532 }
///   ]
/// }
/// ```
struct DailyUsageRawCache: Decodable {
    let updatedAt: LenientDate?
    let days: [DailyUsageRawDay]

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case days
    }
}

struct DailyUsageRawDay: Decodable {
    let date: String
    let totalTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double

    enum CodingKeys: String, CodingKey {
        case date
        case totalTokens         = "total_tokens"
        case inputTokens         = "input_tokens"
        case outputTokens        = "output_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens     = "cache_read_tokens"
        case cost
    }
}

// MARK: - Parsed App Models

/// Parsed Claude quota ready for display.
struct ClaudeQuota {
    let fiveHourRemaining: Double   // 0–100, remaining %
    let fiveHourResetsAt: Date?
    let sevenDayRemaining: Double   // 0–100, remaining %
    let sevenDayResetsAt: Date?
    let updatedAt: Date?
}

/// Parsed Gemini quota ready for display.
struct GeminiQuota {
    let remaining: Double           // 0–100, remaining %
    let resetsAt: Date?
    let modelLabel: String
    let fetchedAt: Date?
}

/// Parsed daily Claude Code token usage, ready for display.
struct DailyUsage {

    struct Day: Identifiable {
        let id = UUID()
        let date: Date?
        let shortLabel: String      // "Mon", "Tue", … (or the raw date if unparseable)
        let totalTokens: Int
        let cost: Double
    }

    /// Chronological, oldest first. `days.last` is today.
    let days: [Day]
    let updatedAt: Date?

    var today: Day? { days.last }

    /// Largest single-day token count in the window (for bar scaling); never 0.
    var peakTokens: Int { max(1, days.map(\.totalTokens).max() ?? 1) }

    /// Sum across the whole window.
    var windowTokens: Int { days.reduce(0) { $0 + $1.totalTokens } }
    var windowCost: Double { days.reduce(0) { $0 + $1.cost } }
}

// MARK: - Data Loader

enum QuotaDataLoader {

    // MARK: Public

    static func loadClaude() -> ClaudeQuota? {
        guard let data = readFile("~/.claude/rate_limits_cache.json"),
              let raw = try? JSONDecoder().decode(ClaudeRawCache.self, from: data)
        else { return nil }

        return ClaudeQuota(
            fiveHourRemaining: max(0, 100.0 - raw.fiveHour.usedPercentage),
            fiveHourResetsAt:  raw.fiveHour.resetsAt?.date,
            sevenDayRemaining: max(0, 100.0 - raw.sevenDay.usedPercentage),
            sevenDayResetsAt:  raw.sevenDay.resetsAt?.date,
            updatedAt:         Date(timeIntervalSince1970: raw.updatedAt)
        )
    }

    static func loadGemini() -> GeminiQuota? {
        guard let data = readFile("~/.antigravity/quota_cache.json"),
              let raw = try? JSONDecoder().decode(GeminiRawCache.self, from: data)
        else { return nil }

        return GeminiQuota(
            remaining:  raw.remainingPercentage,
            resetsAt:   raw.resetsAt?.date,
            modelLabel: raw.label,
            fetchedAt:  raw.updatedAt?.date
        )
    }

    static func loadDailyUsage() -> DailyUsage? {
        guard let data = readFile("~/.quota-menubar/daily_usage_cache.json"),
              let raw = try? JSONDecoder().decode(DailyUsageRawCache.self, from: data),
              !raw.days.isEmpty
        else { return nil }

        let isoDay = DateFormatter()
        isoDay.locale = Locale(identifier: "en_US_POSIX")
        isoDay.dateFormat = "yyyy-MM-dd"

        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "en_US_POSIX")
        weekday.dateFormat = "EEE"

        let days = raw.days.map { d -> DailyUsage.Day in
            let date = isoDay.date(from: d.date)
            return DailyUsage.Day(
                date: date,
                shortLabel: date.map { weekday.string(from: $0) } ?? d.date,
                totalTokens: d.totalTokens,
                cost: d.cost
            )
        }

        return DailyUsage(days: days, updatedAt: raw.updatedAt?.date)
    }

    // MARK: Private Helpers

    private static func readFile(_ path: String) -> Data? {
        let expanded = NSString(string: path).expandingTildeInPath
        return FileManager.default.contents(atPath: expanded)
    }
}

// MARK: - Lenient Date Decoding

/// A timestamp that may arrive as a Unix epoch (seconds, as a JSON number)
/// or as an ISO-8601 string. Both quota cache files have switched between
/// these representations across upstream updates, so every date field from
/// them is decoded through this wrapper. `date` is `nil` when the value is
/// missing, null, or in a shape we don't recognise.
struct LenientDate: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let epoch = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: epoch)
        } else if let string = try? container.decode(String.self) {
            date = Self.parseISO(string)
        } else {
            date = nil
        }
    }

    /// Parse ISO 8601 strings like `"2026-08-10T20:40:00.370598+00:00"` or `"…Z"`.
    static func parseISO(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Display Helpers

enum QuotaFormatting {

    /// Map a remaining percentage (0–100) to a continuous RGB color.
    /// 100% → systemGreen (#34C759)
    ///  50% → systemOrange (#FF9500)
    ///   0% → systemRed   (#FF3B30)
    static func color(forPercent pct: Double) -> (r: Double, g: Double, b: Double) {
        let clamped = max(0, min(100, pct))

        let r, g, b: Double
        if clamped >= 50 {
            let t = (clamped - 50) / 50
            r = Double(0xFF) + t * Double(0x34 - 0xFF)
            g = Double(0x95) + t * Double(0xC7 - 0x95)
            b = Double(0x00) + t * Double(0x59 - 0x00)
        } else {
            let t = clamped / 50
            r = Double(0xFF) + t * Double(0xFF - 0xFF)
            g = Double(0x3B) + t * Double(0x95 - 0x3B)
            b = Double(0x30) + t * Double(0x00 - 0x30)
        }
        return (r / 255, g / 255, b / 255)
    }

    /// Format a future date as a concise countdown relative to `now`.
    /// e.g., "4h 44m", "2d 3h", "12m", or "Resetting…" if past.
    static func countdown(to target: Date?, from now: Date = .now) -> String? {
        guard let target else { return nil }
        let remaining = target.timeIntervalSince(now)
        guard remaining > 0 else { return "Resetting…" }

        let total = Int(remaining)
        let days    = total / 86400
        let hours   = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Format data age in concise English. e.g., "Updated 5m ago".
    static func age(of fetchedDate: Date?, from now: Date = .now) -> String? {
        guard let fetchedDate else { return nil }
        let seconds = now.timeIntervalSince(fetchedDate)
        guard seconds >= 0 else { return nil }

        let minutes = Int(seconds / 60)
        if minutes >= 120 {
            return "Updated \(minutes / 60)h ago"
        } else if minutes >= 1 {
            return "Updated \(minutes)m ago"
        } else {
            return "Updated just now"
        }
    }

    /// Seconds after which a cache counts as stale. The slowest poller runs
    /// every 5 minutes, so 15 minutes means at least two polls in a row failed.
    static let staleAfter: TimeInterval = 900

    /// Whether data is stale (older than `staleAfter`).
    static func isStale(_ fetchedDate: Date?, from now: Date = .now) -> Bool {
        guard let fetchedDate else { return false }
        return now.timeIntervalSince(fetchedDate) > staleAfter
    }

    /// Compact token count. e.g. 27_603_168 → "27.6M", 903_954 → "904K", 290 → "290".
    static func tokens(_ n: Int) -> String {
        let value = Double(n)
        if n >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        } else {
            return "\(n)"
        }
    }

    /// Dollar amount. e.g. 10.3532 → "$10.35", 0 → "$0.00".
    static func money(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }
}
