//
//  AppModeView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/22/26.
//

import SwiftUI

struct AppModeView: View {
    var applicationStore: ApplicationStore
    
    var body: some View {
        VStack {
            AppHeaderView()
            
            Spacer()
            
            Button {
                
            } label: {
                Text("App Mode")
            }
            
            Button {
                
            } label: {
                Text("Debug Mode")
            }
            
        }
    }
}

#Preview {
    AppModeView(applicationStore: ApplicationStore())
}
