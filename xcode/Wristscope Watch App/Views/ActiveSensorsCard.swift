//
//  ActiveSensorsCard.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import SwiftUI


//struct ActiveSensorsCard: View {
//    let sources: [Motion.Source]
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 6) {
//            Text("Active Sensors")
//                .font(.headline)
//
//            if sources.isEmpty {
//                Text("None available on this device")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
//            } else {
//                ForEach(sources, id: \.self) { source in
//                    Label {
//                        Text(source.displayName)
//                    } icon: {
//                        Image(systemName: source.systemImage)
//                            .foregroundStyle(.green)
//                    }
//                    .font(.footnote)
//                }
//            }
//        }
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .padding(10)
//        .background(.gray.opacity(0.18), in: .rect(cornerRadius: 14))
//        .accessibilityElement(children: .combine)
//    }
//}
//
//#Preview("All sensors") {
//    ActiveSensorsCard(sources: Motion.Source.allCases)
//}
//
//#Preview("No sensors") {
//    ActiveSensorsCard(sources: [])
//}
