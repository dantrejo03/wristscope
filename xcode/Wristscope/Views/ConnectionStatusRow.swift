//
//  ConnectionStatusRow.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/14/26.
//

import SwiftUI


struct ConnectionStatusRow: View {
    let status: ConnectionStatus

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                Text(status.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: status.systemImage)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: status.tone == .pending)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch status.tone {
        case .pending: .gray
        case .ok: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

#Preview("All states") {
    List {
        ConnectionStatusRow(status: ConnectionStatus(.activating))
        ConnectionStatusRow(status: ConnectionStatus(.activated(WatchState(isPaired: true, isWatchAppInstalled: true, isReachable: true))))
        ConnectionStatusRow(status: ConnectionStatus(.activated(WatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false))))
        ConnectionStatusRow(status: ConnectionStatus(.activated(WatchState(isPaired: true, isWatchAppInstalled: false, isReachable: false))))
        ConnectionStatusRow(status: ConnectionStatus(.activated(WatchState(isPaired: false, isWatchAppInstalled: false, isReachable: false))))
        ConnectionStatusRow(status: ConnectionStatus(.failed(nil)))
    }
}
