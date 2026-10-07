//
//  QuotaMenuBarView.swift
//  QuotaMenuBar
//
//  The dropdown panel shown when clicking the menu bar item.
//  Apple HIG design: clarity, deference, depth.
//

import SwiftUI

// MARK: - Main Dropdown View

struct QuotaMenuBarView: View {
    @Bindable var viewModel: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Claude Section ──────────────────────────────────
            if let claude = viewModel.claude {
                claudeSection(claude)
            } else {
                notConfiguredRow(icon: "cloud", name: "Claude")
            }

            Divider()
                .padding(.vertical, 6)

            // ── Gemini Section ──────────────────────────────────
            if let gemini = viewModel.gemini {
                geminiSection(gemini)
            } else {
                notConfiguredRow(icon: "sparkles", name: "Gemini")
            }

            Divider()
                .padding(.vertical, 6)

            // ── Claude Code Usage Section ───────────────────────
            if let usage = viewModel.dailyUsage {
                usageSection(usage)
            } else {
                notConfiguredRow(icon: "chart.bar", name: "Usage")
            }

            Divider()
                .padding(.vertical, 6)

            // ── Footer ──────────────────────────────────────────
            Button(action: { viewModel.loadData() }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12))

            Divider()
                .padding(.vertical, 4)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit QuotaMenuBar")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
        }
        .padding(12)
        .frame(width: 260)
        .background(panelBackground)
    }

    /// Panel backdrop. Not pure white: a translucent material with a faint
    /// tint so secondary/tertiary text keeps enough contrast, in both
    /// light and dark appearance.
    private var panelBackground: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle().fill(Color.primary.opacity(0.04))
        }
        .ignoresSafeArea()
    }

    // MARK: - Claude Section

    @ViewBuilder
    private func claudeSection(_ claude: ClaudeQuota) -> some View {
        // Section header
        sectionHeader(icon: "cloud", name: "Claude")

        // 5-hour quota
        quotaRow(
            label: "5h",
            percent: claude.fiveHourRemaining,
            resetsAt: claude.fiveHourResetsAt
        )
        .padding(.top, 6)

        // 7-day quota
        quotaRow(
            label: "7d",
            percent: claude.sevenDayRemaining,
            resetsAt: claude.sevenDayResetsAt
        )
        .padding(.top, 8)

        // Updated age
        ageRow(fetchedDate: claude.updatedAt, staleHint: "session may have expired, re-run setup-claude-auth.sh")
            .padding(.top, 4)
    }

    // MARK: - Gemini Section

    @ViewBuilder
    private func geminiSection(_ gemini: GeminiQuota) -> some View {
        // Section header
        sectionHeader(icon: "sparkles", name: "Gemini")

        // Quota
        quotaRow(
            label: nil,
            percent: gemini.remaining,
            resetsAt: gemini.resetsAt
        )
        .padding(.top, 6)

        // Model label
        Text(gemini.modelLabel)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 2)

        // Updated age
        ageRow(fetchedDate: gemini.fetchedAt)
            .padding(.top, 4)
    }

    // MARK: - Claude Code Usage Section

    @ViewBuilder
    private func usageSection(_ usage: DailyUsage) -> some View {
        sectionHeader(icon: "chart.bar.fill", name: "Claude Code Usage")

        // Today — the headline number
        if let today = usage.today {
            HStack(spacing: 6) {
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(QuotaFormatting.tokens(today.totalTokens)) tok")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("·").foregroundStyle(.tertiary)
                Text(QuotaFormatting.money(today.cost))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }

        // Last 7 days
        VStack(spacing: 3) {
            ForEach(usage.days) { day in
                usageDayRow(day, peak: usage.peakTokens, isToday: day.id == usage.today?.id)
            }
        }
        .padding(.top, 7)

        // Window total
        HStack(spacing: 4) {
            Text("7-day total")
            Spacer(minLength: 0)
            Text(QuotaFormatting.tokens(usage.windowTokens))
            Text("·").foregroundStyle(.tertiary)
            Text(QuotaFormatting.money(usage.windowCost))
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.top, 5)

        ageRow(fetchedDate: usage.updatedAt)
            .padding(.top, 4)
    }

    /// One day in the 7-day strip: weekday · bar · token count.
    private func usageDayRow(_ day: DailyUsage.Day, peak: Int, isToday: Bool) -> some View {
        let empty = day.totalTokens == 0

        return HStack(spacing: 6) {
            Text(isToday ? "Today" : day.shortLabel)
                .font(.system(size: 10, weight: isToday ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isToday ? Color.primary : Color.secondary)
                .frame(width: 34, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.tertiary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.55))
                        .frame(width: empty ? 0 : max(2, geo.size.width * CGFloat(day.totalTokens) / CGFloat(peak)))
                }
            }
            .frame(height: 6)

            Text(QuotaFormatting.tokens(day.totalTokens))
                .font(.system(size: 10, weight: isToday ? .semibold : .regular, design: .rounded))
                .foregroundStyle(empty ? Color.secondary.opacity(0.5) : (isToday ? Color.primary : Color.secondary))
                .frame(width: 46, alignment: .trailing)

            Text(empty ? "" : QuotaFormatting.money(day.cost))
                .font(.system(size: 10, weight: isToday ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isToday ? Color.primary : Color.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(icon: String, name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(name)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    /// A single quota display: label + progress bar + percentage + countdown.
    @ViewBuilder
    private func quotaRow(label: String?, percent: Double, resetsAt: Date?) -> some View {
        let rgb = QuotaFormatting.color(forPercent: percent)
        let tintColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Optional label (e.g. "5h", "7d")
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }

                // Progress bar
                quotaProgressBar(percent: percent, tintColor: tintColor)
                    .frame(height: 6)

                // Percentage
                Text("\(Int(percent))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(tintColor)
                    .frame(width: 40, alignment: .trailing)
            }

            // Countdown
            if let cd = QuotaFormatting.countdown(to: resetsAt) {
                HStack(spacing: 0) {
                    if label != nil {
                        Spacer()
                            .frame(width: 28) // align with bar (22 + 6 spacing)
                    }
                    Text("Resets in \(cd)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let resetsAt {
                        Text(" (\(resetsAt.formatted(.dateTime.hour().minute())))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// A rounded progress bar with continuous color gradient.
    private func quotaProgressBar(percent: Double, tintColor: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(.tertiary)

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(tintColor)
                    .frame(width: max(0, geo.size.width * CGFloat(min(100, max(0, percent))) / 100))
            }
        }
    }

    /// "Updated Xm ago" row, with stale warning.
    @ViewBuilder
    private func ageRow(fetchedDate: Date?, staleHint: String? = nil) -> some View {
        if let ageText = QuotaFormatting.age(of: fetchedDate) {
            if QuotaFormatting.isStale(fetchedDate) {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Stale — \(staleHint ?? ageText)")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color(.systemRed))
            } else {
                Text(ageText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Placeholder for unconfigured data source.
    private func notConfiguredRow(icon: String, name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13))
            Text("\(name): Not configured")
                .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
    }
}
