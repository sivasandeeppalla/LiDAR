//
//  LiDARPOCApp.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI

@main
struct LiDARPOCApp: App {
    init() {
        // Clear history downloads folder on app launch
        APIService.shared.clearHistoryDownloads()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
