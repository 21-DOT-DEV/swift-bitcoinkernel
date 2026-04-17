//
//  TorStatusView.swift
//  21-DOT-DEV/Bitcoin
//
//  Copyright (c) 2022 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import SwiftUI

/// Unified status display for the shared ``TorViewModel``.
///
/// Renders the appropriate row(s) for the current display state:
/// - `.starting`: progress bar + percent + bootstrap summary.
/// - `.failed` (with pending retry): live countdown + attempt number.
/// - `.failed` (exhausted retries): inline "Retry" button.
/// - `.running`: SOCKS proxy endpoint.
/// - `.disabled` / `.stopping`: nothing.
///
/// Used inside both NodeApp's Privacy `Form` section and KernelApp's Tor
/// `List` section — SwiftUI handles the container styling automatically.
struct TorStatusView: View {
    @Bindable var viewModel: TorViewModel

    var body: some View {
        switch viewModel.displayState {
        case .starting:
            startingRows

        case .failed:
            if let retryAt = viewModel.nextRetryAt {
                RetryCountdownRow(
                    target: retryAt,
                    attempt: viewModel.failureCount,
                    total: viewModel.maxAttempts
                )
            } else {
                giveUpRow
            }

        case .running:
            if let endpoint = viewModel.proxyAddress {
                LabeledContent("SOCKS Proxy") {
                    Text(endpoint)
                        .font(.caption.monospaced())
                }
            }

        case .disabled, .stopping:
            EmptyView()
        }
    }

    // MARK: - State-specific subviews

    @ViewBuilder
    private var startingRows: some View {
        HStack {
            ProgressView(value: Double(viewModel.bootstrapProgress), total: 100)
            Text("\(viewModel.bootstrapProgress)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if !viewModel.bootstrapSummary.isEmpty {
            Text(viewModel.bootstrapSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var giveUpRow: some View {
        HStack {
            Label(
                "Tor failed after \(viewModel.failureCount) attempts",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.red)
            .font(.caption)

            Spacer()

            Button("Retry") {
                viewModel.retry()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - RetryCountdownRow

/// Live-updating countdown to the next auto-retry attempt.
///
/// Drives a 1s timer tick to update the remaining seconds text without
/// forcing the whole view tree to re-render more often than necessary.
private struct RetryCountdownRow: View {
    let target: Date
    /// Failures so far — the next attempt number is `attempt + 1`.
    let attempt: Int
    /// Total attempts the view model will make before give-up
    /// (`TorViewModel.maxAttempts = backoffSchedule.count + 1`).
    let total: Int

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(.orange)
            Text(countdownText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .onReceive(tick) { now = $0 }
    }

    private var countdownText: String {
        let remaining = max(0, Int(target.timeIntervalSince(now)))
        return "Retrying in \(remaining)s (attempt \(attempt + 1) of \(total))"
    }
}
