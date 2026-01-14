//
//  LiDARPOCApp.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI
import UIKit

@main
struct LiDARPOCApp: App {
    init() {
        // Keep screen awake for entire app lifecycle
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Clear history downloads folder on app launch
        APIService.shared.clearHistoryDownloads()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
