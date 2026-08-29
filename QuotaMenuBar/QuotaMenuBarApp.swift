//
//  QuotaMenuBarApp.swift
//  QuotaMenuBar
//
//  Menu bar agent app — lives only in the macOS menu bar (LSUIElement = YES).
//  Uses MenuBarExtra instead of WindowGroup.
//

import SwiftUI

@main
struct QuotaMenuBarApp: App {
    @State private var viewModel = QuotaViewModel()

    var body: some Scene {
        MenuBarExtra {
            QuotaMenuBarView(viewModel: viewModel)
        } label: {
            Text(viewModel.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
