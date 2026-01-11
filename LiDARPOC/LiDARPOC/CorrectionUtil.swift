//
//  CorrectionUti.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 06/01/26.
//
import Foundation
import SwiftUI

struct QuadPoints {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
}


struct ImageTransform {
    let imageSize: CGSize
    let viewSize: CGSize

    var scale: CGFloat {
        min(viewSize.width / imageSize.width,
            viewSize.height / imageSize.height)
    }

    var offset: CGPoint {
        CGPoint(
            x: (viewSize.width - imageSize.width * scale) / 2,
            y: (viewSize.height - imageSize.height * scale) / 2
        )
    }

    func imageToView(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: p.x * scale + offset.x,
            y: p.y * scale + offset.y
        )
    }

    func viewToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x - offset.x) / scale,
            y: (p.y - offset.y) / scale
        )
    }
}


struct CornerHandle: View {
    let position: CGPoint
    let onDrag: (CGPoint) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.green)
            .frame(width: 16, height: 16)
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { onDrag($0.location) }
            )
    }
}


struct QuadShape: Shape {
    let points: QuadPoints

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: points.topLeft)
        p.addLine(to: points.topRight)
        p.addLine(to: points.bottomRight)
        p.addLine(to: points.bottomLeft)
        p.closeSubpath()
        return p
    }
}


struct MagnifierView: View {
    let image: UIImage
    let imagePoint: CGPoint
    let offset: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaleEffect(2)
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.green, lineWidth: 2))
            .offset(offset)
    }
}
