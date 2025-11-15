//
//  SimpleTreadmillSyncApp.swift
//  TreadmillSync
//
//  Simplified app entry point - no background modes or complex lifecycle
//

import SwiftUI

@main
struct SimpleTreadmillSyncApp: App {
    var body: some Scene {
        WindowGroup {
            SimpleMainView()
        }
    }
}
