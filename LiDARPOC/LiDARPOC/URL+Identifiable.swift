//
//  URL+Identifiable.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import Foundation

extension URL: Identifiable {
    public var id: String {
        self.path
    }
}

