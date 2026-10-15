//
//  QuotaViewModel.swift
//  QuotaMenuBar
//
//  Observable view model that loads quota data and refreshes every 30 seconds.
//  File I/O runs on a background thread; UI state updates on MainActor.
//

import Foundation

@Observable
final class QuotaViewModel {

    // MARK: - Published State

    var claude: ClaudeQuota?
    var gemini: GeminiQuota?
    var dailyUsage: DailyUsage?

    /// Timestamp of the last refresh (for debugging / display).
    var lastRefresh: Date?

    // MARK: - Private

    private var timerTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {
        loadData()
        startTimer()
    }

    deinit {
        timerTask?.cancel()
    }

    // MARK: - Public

    /// Trigger a one-off refresh (e.g. from the Refresh button).
    func loadData() {
        print("🔄 loadData() called")
        Task.detached { [weak self] in
            let c = QuotaDataLoader.loadClaude()
            let g = QuotaDataLoader.loadGemini()
            let u = QuotaDataLoader.loadDailyUsage()
            guard let vm = self else { return }
            await MainActor.run {
                vm.claude = c
                vm.gemini = g
                vm.dailyUsage = u
                vm.lastRefresh = .now
                print("✅ loadData() finished, lastRefresh = \(vm.lastRefresh!)")
            }
        }
    }

    // MARK: - Menu Bar Title

    /// The string shown in the macOS menu bar.
    /// Format: `☁ 5h 93% 7d 22% ✦ 90% $7.26` (last part = today's estimated Claude Code cost).
    /// Kept short: on notched MacBooks a long title pushes other menu bar icons out of view.
    /// Uses system default color (no custom color on the title).
    var menuBarTitle: String {
        var parts: [String] = []

        if let c = claude {
            let warn = QuotaFormatting.isStale(c.updatedAt) ? "⚠ " : ""
            parts.append("\(warn)☁ 5h \(Int(c.fiveHourRemaining))%")
            parts.append("7d \(Int(c.sevenDayRemaining))%")
        }

        if let g = gemini {
            parts.append("✦ \(Int(g.remaining))%")
        }

        if let today = dailyUsage?.today, today.totalTokens > 0 {
            parts.append(QuotaFormatting.money(today.cost))
        }

        return parts.isEmpty ? "✦ --" : parts.joined(separator: " ")
    }

    // MARK: - Private

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.loadData()
            }
        }
    }
}
