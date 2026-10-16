//
//  PhoneConnectionView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import SwiftUI

/// Placeholder that shows whether the iPhone can be reached.
struct PhoneConnectionView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: status.symbol)
                .font(.largeTitle)
                .foregroundStyle(status.color)
            Text(status.title)
                .font(.headline)
            Button("Done", action: onDone)
        }
    }

    private var status: (title: String, symbol: String, color: Color) {
        switch WatchConnectivityManager.shared.connection {
        case .activating: ("Connecting…", "iphone", .gray)
        case .failed: ("Connection Failed", "exclamationmark.triangle.fill", .red)
        case .activated(_, isCompanionAppInstalled: false): ("No iPhone App", "iphone.slash", .red)
        case .activated(isReachable: false, _): ("Not Reachable", "iphone.slash", .orange)
        case .activated(isReachable: true, _): ("Connected", "iphone.radiowaves.left.and.right", .green)
        }
    }
}

#Preview {
    PhoneConnectionView(onDone: {})
}
