//
//  CountdownView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI

struct CountdownView: View {
    var onFinish: () -> Void

    @State private var count = 3

    var body: some View {
        Text("\(count)")
            .font(.system(size: 90, weight: .bold, design: .rounded))
            .foregroundStyle(.green)
            .contentTransition(.numericText(countsDown: true))
            .task {
                // .task is cancelled automatically if the view goes away
                while count > 1 {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    withAnimation { count -= 1 }
                }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                onFinish()
            }
    }
}

#Preview {
    CountdownView(onFinish: {})
}
