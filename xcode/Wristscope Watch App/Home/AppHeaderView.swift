//
//  AppHeaderView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/15/26.
//

import SwiftUI

struct AppHeaderView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("Wristscope")
                .font(.headline)
        }
    }
}

#Preview {
    AppHeaderView()
}
