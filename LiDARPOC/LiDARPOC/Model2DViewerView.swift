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
        case swapMode
    }

    let image: UIImage
    let fileId: String

    @Environment(\.dismiss) var dismiss

    @State private var viewState: ViewState = .initial
    @State private var tapLocation: CGPoint = .zero
    @State private var imageSize: CGSize = .zero
    @State private var pixelTapLocation: CGPoint = .zero

    @State private var isProcessing = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    @State private var assignedImage: UIImage?
    @State private var boundingBox: APIService.Box?
    @State private var rotatedBbox: [APIService.SwapPointsRequest]?
    @State private var refinedBox: [APIService.SwapPointsRequest]?

    @State private var measurements: APIService.MeasurementResponse?

    @State private var ackroImageBase64 = ""
    @State private var swapImageBase64 = ""

    var displayedImage: UIImage {
        assignedImage ?? image
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {

                // MARK: - Top bar
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                    .padding()
                }

                Spacer()

                // MARK: - Image + Box
                GeometryReader { outerGeo in
                    Image(uiImage: displayedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(
                            GeometryReader { imgGeo in
                                Color.clear
                                    .onAppear { imageSize = imgGeo.size }
                                    .onChange(of: imgGeo.size) { imageSize = $0 }
                            }
                        )

                        // 🔴 Rotated draggable box
                        .overlay(
                            GeometryReader { geo in
                                ZStack {
                                    drawRotatedBoundingBox(geo: geo)
                                }
                            }
                        )

                        // 👆 Tap anywhere
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    handleTap(at: value.location)
                                }
                        )
                }

                Spacer()

                // MARK: - Bottom panel
                VStack {
                    switch viewState {

                    case .initial:
                        Text("Image Point: (\(Int(pixelTapLocation.x)), \(Int(pixelTapLocation.y)))")
                            .foregroundColor(.green)

                        if isProcessing {
                            ProgressView("Processing...")
                                .tint(.white)
                        } else {
                            Button("Process Image") {
                                getAkroProcessImage()
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .disabled(tapLocation == .zero)
                        }

                    case .processed:
                        if let w = measurements?.width_cm {
                            Text(String(format: "Width: %.2f cm", w))
                                .foregroundColor(.green)
                        }
                        if let h = measurements?.height_cm {
                            Text(String(format: "Height: %.2f cm", h))
                                .foregroundColor(.green)
                        }
                        
                        if isProcessing {
                            ProgressView("Processing...")
                                .tint(.white)
                        } else {
                            Button("Adjust Image") {
                                debugPrint("rotated Box is \(rotatedBbox)")

                                debugPrint("Refined Box is \(refinedBox)")
                                getAkroAdjestedProcessImage()
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .disabled(tapLocation == .zero)
                        }
                       
                    case .swapMode:
                        swapImagesView()
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .padding(.bottom)
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

    // MARK: - Rotated Bounding Box (DRAGGABLE)

    @ViewBuilder
    private func drawRotatedBoundingBox(geo: GeometryProxy) -> some View {
        if let points = refinedBox,
           points.count == 4,
           let cgImage = displayedImage.cgImage {

            let viewSize = geo.size
            let imgWidth = CGFloat(cgImage.width)
            let imgHeight = CGFloat(cgImage.height)

            let scaleX = viewSize.width / imgWidth
            let scaleY = viewSize.height / imgHeight

            let viewPoints = points.map {
                CGPoint(
                    x: CGFloat($0.x) * scaleX,
                    y: CGFloat($0.y) * scaleY
                )
            }

            // Box lines
            Path { path in
                path.move(to: viewPoints[0])
                for i in 1..<viewPoints.count {
                    path.addLine(to: viewPoints[i])
                }
                path.closeSubpath()
            }
            .stroke(Color.green, lineWidth: 2)

            // Draggable corners
            ForEach(viewPoints.indices, id: \.self) { index in
                Circle()
                    .fill(Color.green)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
                    .position(viewPoints[index])
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { value in
                                if viewState == .processed {
                                    updateRotatedPoint(
                                        index: index,
                                        viewLocation: value.location,
                                        viewSize: viewSize,
                                        imageSize: CGSize(width: imgWidth, height: imgHeight)
                                    )
                                }
                            }
                    )
            }
        }
    }

    // MARK: - Helpers

    private func updateRotatedPoint(
        index: Int,
        viewLocation: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize
    ) {
        guard rotatedBbox?.count == 4 else { return }

        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height

        let pixelX = max(0, min(viewLocation.x * scaleX, imageSize.width))
        let pixelY = max(0, min(viewLocation.y * scaleY, imageSize.height))

        refinedBox?[index] = APIService.SwapPointsRequest(
            x: Double(pixelX),
            y: Double(pixelY)
        )
    }

    private func handleTap(at location: CGPoint) {
        tapLocation = location

        if let cgImage = displayedImage.cgImage,
           imageSize.width > 0,
           imageSize.height > 0 {

            let nx = location.x / imageSize.width
            let ny = location.y / imageSize.height

            pixelTapLocation = CGPoint(
                x: nx * CGFloat(cgImage.width),
                y: ny * CGFloat(cgImage.height)
            )
        }
    }

    // MARK: - API Calls (unchanged)

    func getAkroProcessImage() {
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
                       let img = UIImage(data: data) {
                        assignedImage = img
                        ackroImageBase64 = response.image
                    }

                    rotatedBbox = response.prediction?.rotated_bbox
                    refinedBox = response.prediction?.rotated_bbox
                    measurements = response.measurement
                    viewState = .processed
                    alertMessage = "Processing successful"
                    showAlert = true

                case .failure(let error):
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    func getAkroAdjestedProcessImage() {
        isProcessing = true
        APIService.shared.redefinedAkroImage(
            image: image,
            adjustedPoints: refinedBox ?? [],
            fileId: fileId
        ) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success(let response):
                    if let data = Data(base64Encoded: response.image),
                       let img = UIImage(data: data) {
                        assignedImage = img
                        ackroImageBase64 = response.image
                    }
                    rotatedBbox = response.prediction?.rotated_bbox
                    refinedBox = response.prediction?.rotated_bbox
                    measurements = response.measurement
                    viewState = .swapMode
                    alertMessage = "Processing successful"
                    showAlert = true

                case .failure(let error):
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func swapImagesView() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach((0...9).map { "door_\($0)" }, id: \.self) { name in
                    Button {
                        if let img = UIImage(named: name),
                           let data = img.jpegData(compressionQuality: 0.8) {
                            swapAckroImage(swapBase64: data.base64EncodedString())
                        }
                    } label: {
                        Image(name)
                            .resizable()
                            .frame(width: 90, height: 140)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }

    func swapAckroImage(swapBase64: String) {
        guard let points = rotatedBbox else { return }

        APIService.shared.processSwapImage(
            inputImage: ackroImageBase64,
            swapImage: swapBase64,
            points: points
        ) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success(let response):
                    print("✅ Swap success")
                    if let image = response.image_1, let data = Data(base64Encoded: image),
                       let newImage = UIImage(data: data) {
                        self.assignedImage = newImage
                    }
                case .failure(let error):
                    print("❌ Swap failed: \(error.localizedDescription)")
                    self.alertMessage = "Swap Error: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
}

#Preview {
    Model2DViewerView(
        image: UIImage(systemName: "photo")!,
        fileId: ""
    )
}

