//
//  AppView.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/22/26.
//

import SwiftUI

struct AppView: View {
    
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
    AppView()
}
