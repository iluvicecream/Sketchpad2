//
//  ContentView.swift
//  Bench
//
//  Created by perr on 9/5/2569 BE.
//

import SwiftUI

struct ContentView: View {
    @State private var controller = ArduinoController()
    
    var body: some View {
        ArduinoSetupView()
            .environment(controller)
            .frame(width: 500, height: 600)
    }
}

#Preview {
    ContentView()
}
