//
//  WelcomeView.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI

struct WelcomeView: View {
    @State private var showSample3DViewer = false
    @State private var sampleModelURL: URL?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                Image("welcomeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .padding()
                
                Text("VisionMetric")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, -24)
                Text("Powered by Mialo.ai")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                VStack(spacing: 16) {
                    NavigationLink(destination: CameraRecordView()) {
                        HStack {
                            Image(systemName: "camera")
                            Text("Start Recording")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    NavigationLink(destination: RecordingsListView()) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("View Recordings")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        print("🔘 Button tapped - View Sample 3D")
                        print("   Current showSample3DViewer: \(showSample3DViewer)")
                        print("   Current sampleModelURL: \(sampleModelURL?.path ?? "nil")")
                        
                        // Ensure we have a URL
                        if sampleModelURL == nil {
                            sampleModelURL = findSampleModelURL()
                        }
                        
                        if let url = sampleModelURL {
                            print("✅ Using URL: \(url.path)")
                            showSample3DViewer = true
                            print("   Set showSample3DViewer to: \(showSample3DViewer)")
                        } else {
                            print("❌ Could not find lidar.obj in bundle. Make sure it's added to the project target.")
                            // Still show sheet with error message
                            showSample3DViewer = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "cube.fill")
                            Text("View Sample 3D")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
            .padding()
            .sheet(isPresented: $showSample3DViewer) {
                Group {
                    if let modelURL = sampleModelURL {
                        Model3DViewerView(modelURL: modelURL)
                            .onAppear {
                                print("📱 Sheet presented with URL: \(modelURL.path)")
                            }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            Text("Error: Model URL not found")
                                .foregroundColor(.red)
                                .font(.headline)
                            Text("Make sure lidar.obj is added to the project")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .onAppear {
                            print("❌ Sheet presented but sampleModelURL is nil!")
                        }
                    }
                }
            }
            .onChange(of: showSample3DViewer) { newValue in
                print("🔄 showSample3DViewer changed to: \(newValue), sampleModelURL: \(sampleModelURL?.path ?? "nil")")
            }
            .onAppear {
                // Just prepare the model URL, don't show viewer
                sampleModelURL = findSampleModelURL()
            }
        }
    }
    
    /// Find sample 3D model URL in bundle
    /// - Returns: URL if model was found, nil otherwise
    private func findSampleModelURL() -> URL? {
        // Try to find lidar.obj in the bundle
        var objURL: URL?
        
        // Try multiple possible locations
        objURL = Bundle.main.url(forResource: "lidar", withExtension: "obj")
        print("🔍 Looking for lidar.obj in bundle...")
        
        if objURL == nil {
            print("   Not found in root, trying Resources folder...")
            objURL = Bundle.main.url(forResource: "lidar", withExtension: "obj", subdirectory: "Resources")
        }
        
        if objURL == nil {
            print("   Not found in Resources, searching all .obj files...")
            // Try to find any .obj file in bundle
            if let resourcePath = Bundle.main.resourcePath {
                let fileManager = FileManager.default
                if let files = try? fileManager.contentsOfDirectory(atPath: resourcePath) {
                    print("   Found files in bundle: \(files.filter { $0.hasSuffix(".obj") })")
                    for file in files {
                        if file.hasSuffix(".obj") {
                            let fileName = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
                            objURL = Bundle.main.url(forResource: fileName, withExtension: "obj")
                            print("   Found .obj file: \(file)")
                            break
                        }
                    }
                }
            }
        }
        
        if let url = objURL {
            print("✅ Found sample 3D model at: \(url.path)")
            print("   File exists: \(FileManager.default.fileExists(atPath: url.path))")
        } else {
            print("❌ Could not find lidar.obj in bundle")
            print("   Make sure lidar.obj is added to the project and included in the app target")
        }
        
        return objURL
    }
}

#Preview {
    WelcomeView()
}

