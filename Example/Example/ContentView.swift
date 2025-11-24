//
//  ContentView.swift
//  Example
//
//  Created by Jan Aagaard Meier on 24/11/2025.
//

import IduraVerify
import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack {
      Image(systemName: "globe")
        .imageScale(.large)
        .foregroundStyle(.tint)
      Text(IduraVerify.text)
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
