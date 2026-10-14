//
//  ConnectionStatusCard.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import SwiftUI


struct ConnectionStatusCard: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: status.tone == .pending)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.headline)
                Text(status.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.18), in: .rect(cornerRadius: 14))
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
    ScrollView {
        VStack(spacing: 8) {
            ConnectionStatusCard(status: ConnectionStatus(.activating))
            ConnectionStatusCard(status: ConnectionStatus(.activated(isReachable: true, isCompanionAppInstalled: true)))
            ConnectionStatusCard(status: ConnectionStatus(.activated(isReachable: false, isCompanionAppInstalled: true)))
            ConnectionStatusCard(status: ConnectionStatus(.activated(isReachable: false, isCompanionAppInstalled: false)))
            ConnectionStatusCard(status: ConnectionStatus(.failed(nil)))
        }
    }
}
