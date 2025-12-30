//
//  Item.swift
//  screencoach
//
//  Created by yyk on 2025-12-30.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
