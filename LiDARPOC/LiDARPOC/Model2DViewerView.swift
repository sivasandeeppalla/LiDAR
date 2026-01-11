//
//  Model2DViewerView.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 06/01/26.
//

import SwiftUI

struct Model2DViewerView: View {
    enum ViewState {
        case initial
        case processed
    }

    let image: UIImage
    let fileId: String
    @Environment(\.dismiss) var dismiss
    @State var viewState: ViewState = .initial

    @State private var tapLocation: CGPoint = .zero
    @State private var normalizedTapLocation: CGPoint = .zero
    @State private var imageSize: CGSize = .zero

    @State private var isProcessing = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    @State private var assignedImage: UIImage?
    @State private var boundingBox: APIService.Box?
    @State private var rotatedBbox: [APIService.SwapPointsRequest]?
    @State private var measurements: APIService.MeasurementResponse?
    @State private var pixelTapLocation: CGPoint = .zero
    @State private var ackroImageBase64: String = ""
    @State private var swapImageBase64: String = ""

    var displayedImage: UIImage {
        assignedImage ?? image
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                // Top bar
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding()
                }

                Spacer()

                GeometryReader { geometry in
                    ZStack {
                        Image(uiImage: displayedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .background(
                                GeometryReader { imageGeo in
                                    Color.clear
                                        .onAppear { imageSize = imageGeo.size }
                                        .onChange(of: imageGeo.size) { imageSize = $0 }
                                }
                            )

                            // 🔴 ROTATED BOUNDING BOX OVERLAY
                            .overlay(
                                GeometryReader { geo in
                                    ZStack {
                                        if let points = rotatedBbox,
                                           points.count == 4,
                                           let cgImage = displayedImage.cgImage {

                                            let viewSize = geo.size
                                            let imgWidth = CGFloat(cgImage.width)
                                            let imgHeight = CGFloat(cgImage.height)

                                            let scaleX = viewSize.width / imgWidth
                                            let scaleY = viewSize.height / imgHeight

                                            // Convert image-pixel points → view points
                                            let viewPoints: [CGPoint] = points.map {
                                                CGPoint(
                                                    x: CGFloat($0.x) * scaleX,
                                                    y: CGFloat($0.y) * scaleY
                                                )
                                            }

                                            // Draw polygon
                                            Path { path in
                                                path.move(to: viewPoints[0])
                                                for i in 1..<viewPoints.count {
                                                    path.addLine(to: viewPoints[i])
                                                }
                                                path.closeSubpath()
                                            }
                                            .stroke(Color.green, lineWidth: 2)

                                            // Draggable corner points
                                            ForEach(viewPoints.indices, id: \.self) { index in
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 14, height: 14)
                                                    .position(viewPoints[index])
                                                    .gesture(
                                                        DragGesture()
                                                            .onChanged { value in
                                                                updateRotatedPoint(
                                                                    index: index,
                                                                    viewLocation: value.location,
                                                                    viewSize: viewSize,
                                                                    imageSize: CGSize(width: imgWidth, height: imgHeight)
                                                                )
                                                            }
                                                    )
                                            }
                                        }
                                    }
                                }
                            )

                            // Tap overlay
                            .overlay(
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        handleTap(at: location)
                                    }
                            )
                    }
                }

                Spacer()

                VStack {
                    switch viewState {
                    case .initial:
                        Text("View Point: (\(Int(tapLocation.x)), \(Int(tapLocation.y)))")
                            .foregroundColor(.gray)

                        Text("Image Point: (\(Int(pixelTapLocation.x)), \(Int(pixelTapLocation.y)))")
                            .font(.headline)
                            .foregroundColor(.green)

                        Text("Image Size: \(Int(imageSize.width)) x \(Int(imageSize.height))")
                            .font(.caption)
                            .foregroundColor(.gray)

                        if isProcessing {
                            ProgressView("Processing...")
                                .tint(.white)
                        } else {
                            Button {
                                getAkroProcessImage()
                            } label: {
                                Text("Process Image")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            .disabled(tapLocation == .zero)
                            .opacity(tapLocation == .zero ? 0.5 : 1)
                        }

                    case .processed:
                        if let width_cm = measurements?.width_cm {
                            Text(String(format: "Width(cms): %.2f", width_cm))
                                .foregroundColor(.green)
                        }

                        if let height_cm = measurements?.height_cm {
                            Text(String(format: "Height(cms): %.2f", height_cm))
                                .foregroundColor(.green)
                        }

                        swapImagesView()
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                .padding(.bottom, 20)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertMessage.contains("Error") ? "Error" : "Success"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Helpers (UNCHANGED)

    private func handleTap(at location: CGPoint) {
        tapLocation = location

        if imageSize.width > 0, imageSize.height > 0 {
            let normalizedX = location.x / imageSize.width
            let normalizedY = location.y / imageSize.height

            if let cgImage = displayedImage.cgImage {
                pixelTapLocation = CGPoint(
                    x: normalizedX * CGFloat(cgImage.width),
                    y: normalizedY * CGFloat(cgImage.height)
                )
            }
        }
    }

    func getAkroProcessImage() {
        guard tapLocation != .zero else { return }
        isProcessing = true

        APIService.shared.processArucoMarkerImage(
            image: image,
            clickPoint: pixelTapLocation,
            fileId: fileId
        ) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success(let response):
                    if let data = Data(base64Encoded: response.image),
                       let newImage = UIImage(data: data) {
                        self.assignedImage = newImage
                        self.ackroImageBase64 = response.image
                    }
                    self.boundingBox = response.prediction?.box
                    self.rotatedBbox = response.prediction?.rotated_bbox
                    self.measurements = response.measurement
                    self.viewState = .processed
                    self.alertMessage = "Processing successful!"
                    self.showAlert = true

                case .failure(let error):
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private func swapImagesView() -> some View {
        let doors = (0...9).map { "door_\($0)" }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(doors, id: \.self) { name in
                    Button {
                        if let image = UIImage(named: name),
                           let data = image.jpegData(compressionQuality: 0.8) {
                            swapAckroImage(swapBase64: data.base64EncodedString())
                        }
                    } label: {
                        Image(name)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 90, height: 150)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    func swapAckroImage(swapBase64: String) {
        guard !ackroImageBase64.isEmpty,
              let points = rotatedBbox else { return }

        isProcessing = true

        APIService.shared.processSwapImage(
            inputImage: ackroImageBase64,
            swapImage: swapBase64,
            points: points
        ) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                if case .success(let response) = result,
                   let image = response.image_1,
                   let data = Data(base64Encoded: image) {
                    self.assignedImage = UIImage(data: data)
                }
            }
        }
    }
    
    private func updateRotatedPoint(
        index: Int,
        viewLocation: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize
    ) {
        guard rotatedBbox?.count == 4 else { return }

        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height

        // Convert view → image pixel coordinates
        let pixelX = max(0, min(viewLocation.x * scaleX, imageSize.width))
        let pixelY = max(0, min(viewLocation.y * scaleY, imageSize.height))

        rotatedBbox?[index] = APIService.SwapPointsRequest(
            x: Double(pixelX),
            y: Double(pixelY)
        )
    }
}

#Preview {
    Model2DViewerView(image: UIImage(systemName: "photo")!, fileId: "")
}

