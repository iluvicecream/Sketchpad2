//
//  Tag.swift
//  Sketchpad2
//
//  Created by perr on 10/31/2569 BE.
//

import SwiftUI

struct TagView : View {
    var tagText : String
    var tagBgColor : Color
    var tagTextColor : Color
    var tagIcon : String?
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = tagIcon {
                Image(systemName: icon)
                    .font(.footnote)
            }
            
            Text(tagText)
                .font(.footnote)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(tagTextColor)
        .background(
            tagBgColor,
            in: Capsule()
        )
    }
}
