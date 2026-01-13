//
//  Model3DViewerView.swift
//  LiDARPOC
//
//  Created for 3D model viewing and measurement
//

import SwiftUI
import SceneKit
import ModelIO

struct Model3DViewerView: View {
    @Environment(\.dismiss) var dismiss
    let modelURL: URL?
    let fileId: String?
    @State private var selectedPoints: [SCNVector3] = []
    @State private var measurements: [Measurement] = []
    @State private var isMeasurementMode = false
    @State private var showClearAlert = false
    @State private var loadError: String?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadedModelURL: URL?
    @State private var loadedModelNode: SCNNode?
    @State private var isModelLoading: Bool = false
    @StateObject private var apiService = APIService.shared
    
    init(modelURL: URL? = nil, fileId: String? = nil) {
        self.modelURL = modelURL
        self.fileId = fileId
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    // Downloading state
                    if isDownloading {
                        VStack(spacing: 20) {
                            ProgressView(value: downloadProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                                .frame(width: 200)
                            Text("Downloading 3D model... \(Int(downloadProgress * 100))%")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Loading model state
                    else if isModelLoading {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Loading 3D model...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Error message if model fails to load
                    else if let error = loadError {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            Text("Failed to load 3D model")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            if let url = effectiveModelURL {
                                Text("Model URL: \(url.path)")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.7))
                                    .padding(.horizontal)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let modelNode = loadedModelNode {
                        // 3D Scene View
                        SceneKitView(
                            modelNode: modelNode,
                            selectedPoints: $selectedPoints,
                            measurements: $measurements,
                            isMeasurementMode: $isMeasurementMode,
                            loadError: $loadError
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Control Panel
                    VStack(spacing: 12) {
                        // Measurement mode toggle
                        HStack {
                            Button(action: {
                                isMeasurementMode.toggle()
                                if !isMeasurementMode {
                                    // Clear selection when exiting measurement mode
                                    selectedPoints.removeAll()
                                }
                            }) {
                                HStack {
                                    Image(systemName: isMeasurementMode ? "ruler.fill" : "ruler")
                                    Text(isMeasurementMode ? "Measurement Mode ON" : "Measurement Mode OFF")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isMeasurementMode ? Color.green : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            if !selectedPoints.isEmpty || !measurements.isEmpty {
                                Button(action: {
                                    showClearAlert = true
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Clear")
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                        }
                        
                        // Instructions
                        if isMeasurementMode {
                            Text("Tap on the 3D model to mark points (2 points for distance measurement)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Measurement results
                        if !measurements.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(measurements.indices, id: \.self) { index in
                                        HStack {
                                            Text("Measurement \(index + 1):")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            Spacer()
                                            Text(String(format: "%.2f m", measurements[index].distance))
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.red)
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                }
                
            }
            .navigationTitle("3D Model Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Clear All Measurements?", isPresented: $showClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    selectedPoints.removeAll()
                    measurements.removeAll()
                }
            }
            .onAppear {
                if let fileId = fileId, downloadedModelURL == nil {
                    // Check cache first
                    if let cachedFile = apiService.getCachedFile(fileId: fileId, fileType: "processed") {
                        downloadedModelURL = cachedFile
                        loadModelAsync(url: cachedFile)
                    } else {
                        downloadModel()
                    }
                } else if let url = modelURL, loadedModelNode == nil {
                    loadModelAsync(url: url)
                }
            }
            .onDisappear {
                // Ensure auto-lock is re-enabled when leaving the view
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
    
    private var effectiveModelURL: URL? {
        downloadedModelURL ?? modelURL
    }
    
    private func downloadModel() {
        guard let fileId = fileId else { return }
        
        isDownloading = true
        loadError = nil
        downloadProgress = 0.0
        
        // Disable auto-lock while downloading
        UIApplication.shared.isIdleTimerDisabled = true
        
        apiService.downloadFile(fileId: fileId, fileType: "processed", progress: { progress in
            self.downloadProgress = progress
        }) { result in
            DispatchQueue.main.async {
                isDownloading = false
                // Re-enable auto-lock
                UIApplication.shared.isIdleTimerDisabled = false
                
                switch result {
                case .success(let url):
                    downloadedModelURL = url
                    loadModelAsync(url: url)
                    
                case .failure(let error):
                    loadError = "Failed to download 3D model: \(error.localizedDescription)"
                    print("Error downloading 3D model: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadModelAsync(url: URL) {
        guard !isModelLoading else { return }
        
        isModelLoading = true
        loadError = nil
        
        // Run on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            print("🧵 Starting background model load for: \(url.path)")
            
            if let node = self.loadOBJModel(from: url) {
                // Center the model immediately
                let boundingBox = node.boundingBox
                let center = SCNVector3(
                    (boundingBox.min.x + boundingBox.max.x) / 2,
                    (boundingBox.min.y + boundingBox.max.y) / 2,
                    (boundingBox.min.z + boundingBox.max.z) / 2
                )
                node.position = SCNVector3(-center.x, -center.y, -center.z)
                
                DispatchQueue.main.async {
                    print("✅ Background load complete, updating UI")
                    self.loadedModelNode = node
                    self.isModelLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    print("❌ Background load failed")
                    self.isModelLoading = false
                    // loadError is set inside loadOBJModel
                }
            }
        }
    }
    
    private func loadOBJModel(from url: URL) -> SCNNode? {
        print("📂 Attempting to load OBJ from: \(url.path)")
        print("📂 URL scheme: \(url.scheme ?? "none")")
        print("📂 File exists: \(FileManager.default.fileExists(atPath: url.path))")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            let errorMsg = "OBJ file not found at: \(url.path)"
            print("❌ ERROR: \(errorMsg)")
            DispatchQueue.main.async {
                self.loadError = errorMsg
            }
            return nil
        }
        
        // Try loading directly as SceneKit scene (supports .obj files)
        print("🔍 Trying to load with SCNScene...")
        if let scene = try? SCNScene(url: url, options: nil) {
            print("✅ Successfully loaded with SCNScene")
            // Get all child nodes from the scene
            let rootNode = SCNNode()
            
            // Add all nodes from the scene to our root node
            for childNode in scene.rootNode.childNodes {
                rootNode.addChildNode(childNode)
            }
            
            // Only enhance existing materials, don't replace them
            func enhanceMaterialsIfNeeded(to node: SCNNode) {
                if let geometry = node.geometry {
                    // Only enhance existing materials, don't replace them
                    for material in geometry.materials {
                        // Add specular for better lighting if not already set
                        if material.specular.contents == nil {
                            material.specular.contents = UIColor.white
                        }
                        // Add slight shininess if not set
                        if material.shininess == 0 {
                            material.shininess = 0.5
                        }
                    }
                    // If no materials exist, add a default one (shouldn't happen with OBJ files)
                    if geometry.materials.isEmpty {
                        let material = SCNMaterial()
                        material.diffuse.contents = UIColor.white
                        material.specular.contents = UIColor.white
                        material.shininess = 0.5
                        geometry.materials = [material]
                    }
                }
                for child in node.childNodes {
                    enhanceMaterialsIfNeeded(to: child)
                }
            }
            
            enhanceMaterialsIfNeeded(to: rootNode)
            
            return rootNode.childNodes.isEmpty ? nil : rootNode
        } else {
            print("❌ SCNScene failed, trying Model I/O fallback...")
        }
        
        // Fallback: Try using Model I/O
        print("🔍 Trying Model I/O...")
        let asset = MDLAsset(url: url)
        print("📊 Asset object count: \(asset.count)")
        
        guard asset.count > 0 else {
            let errorMsg = "No objects found in OBJ file"
            print("❌ ERROR: \(errorMsg)")
            DispatchQueue.main.async {
                self.loadError = errorMsg
            }
            return nil
        }
        
        // Use Model I/O to create a temporary scene file, then load it with SceneKit
        // Using a unique temp file name to avoid collisions
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_model_\(UUID().uuidString).obj")
        
        do {
            try asset.export(to: tempURL)
            
            // Try loading the exported file
            if let tempScene = try? SCNScene(url: tempURL, options: nil) {
                let rootNode = SCNNode()
                
                for childNode in tempScene.rootNode.childNodes {
                    rootNode.addChildNode(childNode)
                }
                
                // Enhance materials
                func enhanceMaterialsIfNeeded(to node: SCNNode) {
                    if let geometry = node.geometry {
                        for material in geometry.materials {
                            if material.specular.contents == nil {
                                material.specular.contents = UIColor.white
                            }
                            if material.shininess == 0 {
                                material.shininess = 0.5
                            }
                        }
                        if geometry.materials.isEmpty {
                            let material = SCNMaterial()
                            material.diffuse.contents = UIColor.white
                            material.specular.contents = UIColor.white
                            material.shininess = 0.5
                            geometry.materials = [material]
                        }
                    }
                    for child in node.childNodes {
                        enhanceMaterialsIfNeeded(to: child)
                    }
                }
                
                enhanceMaterialsIfNeeded(to: rootNode)
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                
                return rootNode.childNodes.isEmpty ? nil : rootNode
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("ERROR: Failed to export/load OBJ file: \(error.localizedDescription)")
        }
        
        return nil
    }
        
}

struct Measurement {
    let point1: SCNVector3
    let point2: SCNVector3
    let distance: Float
}

// SceneKit View Wrapper
struct SceneKitView: UIViewRepresentable {
    let modelNode: SCNNode
    @Binding var selectedPoints: [SCNVector3]
    @Binding var measurements: [Measurement]
    @Binding var isMeasurementMode: Bool
    @Binding var loadError: String?
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = UIColor.black
        scnView.antialiasingMode = .multisampling4X
        
        print("🎬 Initializing SceneKit view with pre-loaded node")
        
        // Setup scene
        setupScene(in: scnView)
        
        // Log scene state after setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎬 Scene setup complete. Root node children: \(scene.rootNode.childNodes.count)")
            if scene.rootNode.childNodes.isEmpty {
                print("⚠️ WARNING: Scene has no child nodes - model may not have loaded")
            }
        }
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
        
        context.coordinator.scnView = scnView
        
        return scnView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        context.coordinator.selectedPoints = selectedPoints
        context.coordinator.measurements = measurements
        context.coordinator.isMeasurementMode = isMeasurementMode
        
        // Update visualization
        context.coordinator.updateVisualization()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func setupScene(in scnView: SCNView) {
        guard let scene = scnView.scene else {
            print("ERROR: Scene is nil")
            DispatchQueue.main.async {
                loadError = "Failed to initialize scene"
            }
            return
        }
        
        // Add the pre-loaded model node
        scene.rootNode.addChildNode(modelNode)
        print("✅ Added pre-loaded model node to scene")
        
        // Add lighting (dull/darker for better visibility)
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 100 // Further reduced intensity for duller appearance
        lightNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(lightNode)
        
        // Add ambient light (much reduced for duller appearance)
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.black.withAlphaComponent(0.25) // Further reduced to 0.25 for duller look
        scene.rootNode.addChildNode(ambientLight)
        
        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
    }
    

    
    class Coordinator: NSObject {
        var parent: SceneKitView
        weak var scnView: SCNView?
        var selectedPoints: [SCNVector3] = []
        var measurements: [Measurement] = []
        var isMeasurementMode: Bool = false
        var pointNodes: [SCNNode] = []
        var lineNodes: [SCNNode] = []
        
        init(_ parent: SceneKitView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView,
                  isMeasurementMode,
                  gesture.state == .ended else { return }
            
            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: nil)
            
            guard let hitResult = hitResults.first else { return }
            
            let worldPosition = hitResult.worldCoordinates
            
            // Add point
            selectedPoints.append(worldPosition)
            parent.selectedPoints = selectedPoints
            
            // If we have 2 points, create measurement
            if selectedPoints.count == 2 {
                let distance = calculateDistance(selectedPoints[0], selectedPoints[1])
                let measurement = Measurement(point1: selectedPoints[0], point2: selectedPoints[1], distance: distance)
                
                measurements.append(measurement)
                parent.measurements = measurements
                
                // Reset for next measurement
                selectedPoints.removeAll()
                parent.selectedPoints = []
            }
            
            updateVisualization()
        }
        
        func updateVisualization() {
            guard let scene = scnView?.scene else { return }
            
            // Remove old visualization nodes
            pointNodes.forEach { $0.removeFromParentNode() }
            lineNodes.forEach { $0.removeFromParentNode() }
            pointNodes.removeAll()
            lineNodes.removeAll()
            
            // Draw points
            for (index, point) in selectedPoints.enumerated() {
                let sphere = SCNSphere(radius: 0.02)
                sphere.firstMaterial?.diffuse.contents = UIColor.red
                let sphereNode = SCNNode(geometry: sphere)
                sphereNode.position = point
                scene.rootNode.addChildNode(sphereNode)
                pointNodes.append(sphereNode)
                
                // Add label
                let text = SCNText(string: "P\(index + 1)", extrusionDepth: 0.01)
                text.firstMaterial?.diffuse.contents = UIColor.red
                text.font = UIFont.systemFont(ofSize: 0.1)
                let textNode = SCNNode(geometry: text)
                textNode.position = SCNVector3(point.x, point.y + 0.05, point.z)
                scene.rootNode.addChildNode(textNode)
                pointNodes.append(textNode)
            }
            
            // Draw lines for measurements
            for measurement in measurements {
                let line = createLine(from: measurement.point1, to: measurement.point2)
                scene.rootNode.addChildNode(line)
                lineNodes.append(line)
                
                // Add distance label at midpoint
                let midpoint = SCNVector3(
                    (measurement.point1.x + measurement.point2.x) / 2,
                    (measurement.point1.y + measurement.point2.y) / 2,
                    (measurement.point1.z + measurement.point2.z) / 2
                )
                
                let distanceText = SCNText(string: String(format: "%.2f", measurement.distance), extrusionDepth: 0.01)
                distanceText.firstMaterial?.diffuse.contents = UIColor.red
                distanceText.font = UIFont.systemFont(ofSize: 0.1)
                let textNode = SCNNode(geometry: distanceText)
                textNode.position = SCNVector3(midpoint.x, midpoint.y + 0.05, midpoint.z)
                scene.rootNode.addChildNode(textNode)
                lineNodes.append(textNode)
            }
        }
        
        func createLine(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
            let indices: [Int32] = [0, 1]
            let source = SCNGeometrySource(vertices: [start, end])
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            
            geometry.firstMaterial?.diffuse.contents = UIColor.red
            geometry.firstMaterial?.emission.contents = UIColor.red
            
            return SCNNode(geometry: geometry)
        }
        
        func calculateDistance(_ point1: SCNVector3, _ point2: SCNVector3) -> Float {
            let dx = point2.x - point1.x
            let dy = point2.y - point1.y
            let dz = point2.z - point1.z
            return sqrt(dx * dx + dy * dy + dz * dz)
        }
    }
}

#Preview {
    Model3DViewerView(modelURL: URL(fileURLWithPath: ""), fileId: nil)
}

