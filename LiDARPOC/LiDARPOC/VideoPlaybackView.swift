//
//  VideoPlaybackView.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI
import AVKit
import SceneKit

struct VideoPlaybackView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    let videoURL: URL
    let depthURL: URL?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var observer: NSObjectProtocol?
    @State private var playerError: String?
    @State private var statusObserver: NSKeyValueObservation?
    
    @State private var isUploading = false
    @State private var uploadStatus: String?
    @State private var uploadError: String?
    @State private var objFileURL: URL?
    @State private var isDownloadingModel = false
    @State private var show3DViewer = false
    @State var showAlert: Bool = false
    @State var close: () -> Void = {}
    @State var serverMessage: String = ""
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Top bar with close button
                HStack {
                    Button(action: {
                        player?.pause()
                        // Navigate back to welcome screen
                        // Dismiss current view first
                        dismiss()
                        close()
                        
                        // If we came from CameraRecordView (via navigationDestination),
                        // we need to dismiss that too to get back to WelcomeView
                        // Use a small delay to ensure the first dismiss completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding()
                    
                    Spacer()
                    
                    // View 3D Model button (only show if .obj file is available)
//                    if let objURL = objFileURL {
//                        Button(action: {
//                            show3DViewer = true
//                        }) {
//                            HStack(spacing: 6) {
//                                Image(systemName: "cube.fill")
//                                    .font(.system(size: 18, weight: .bold))
//                                Text("VIEW 3D")
//                                    .font(.system(size: 16, weight: .semibold))
//                            }
//                            .padding(.horizontal, 14)
//                            .padding(.vertical, 10)
//                            .background(Color.green.opacity(0.85))
//                            .foregroundColor(.white)
//                            .cornerRadius(12)
//                        }
//                        .padding(.trailing, 8)
//                    }
                    
                    
                        Button(action: {
                            uploadData()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                Text("Upload")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isUploading ? Color.blue.opacity(0.4) :  Color.blue.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.trailing, 12)
                        .disabled(isUploading)
                   
                }
                .padding(.top, 50)
                
                Spacer()
                
                // Video Player
                if let player = player {
                    VideoPlayerView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = playerError {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Error loading video")
                            .foregroundColor(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }
                
                Spacer()
                
                // Play/Pause controls
                HStack(spacing: 40) {
                    Button(action: {
                        guard let player = player else { return }
                        
                        if isPlaying {
                            player.pause()
                            isPlaying = false
                        } else {
                            player.play()
                            isPlaying = true
                        }
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 50)
                
                // Upload status
               /* if let uploadStatus = uploadStatus {
                    Text(uploadStatus)
                        .font(.footnote)
                        .foregroundColor(.green)
                        .padding(.bottom, 12)
                } else if let uploadError = uploadError {
                    Text(uploadError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.bottom, 12)
                } else
                */
                
                if isUploading {
                    ProgressView("Uploading…")
                        .tint(.white)
                        .padding(.bottom, 12)
                } else if isDownloadingModel {
                    ProgressView("Downloading 3D model…")
                        .tint(.white)
                        .padding(.bottom, 12)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $show3DViewer) {
            if let objURL = objFileURL {
                Model3DViewerView(modelURL: objURL)
            }
        }
        .onAppear {
            print("VideoPlaybackView appeared with URL: \(videoURL.path)")
            setupPlayer()
            checkForExistingObjFile()
        }
        .onDisappear {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
            statusObserver?.invalidate()
            player?.pause()
            player = nil
        }
        .alert(serverMessage.lowercased().contains("error") ? "Error" : "Success", isPresented: $showAlert) {
            Button("OK") {
                if !serverMessage.lowercased().contains("error") {
                    dismiss()
                    close()
                }
            }
        }
    }
    
    private func setupPlayer() {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            let errorMsg = "Video file does not exist at path: \(videoURL.path)"
            print("ERROR: \(errorMsg)")
            playerError = errorMsg
            return
        }
        
        print("Setting up video player with URL: \(videoURL.path)")
        
        let asset = AVAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        
        // Apply video transform to rotate 90 degrees if needed
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = tracks.first {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let preferredTransform = try await videoTrack.load(.preferredTransform)
                    
                    // Check if video is portrait (height > width)
                    let isPortrait = naturalSize.height > naturalSize.width
                    
                    if isPortrait {
                        // Rotate 90 degrees clockwise
                        let rotation = CGAffineTransform(rotationAngle: .pi / 2)
                        let translation = CGAffineTransform(translationX: naturalSize.height, y: 0)
                        let newTransform = rotation.concatenating(translation)
                        
                        // Apply transform to the track
                        try await videoTrack.load(.preferredTransform)
                        // Note: We can't directly modify preferredTransform, so we'll handle it in the view
                    }
                }
            } catch {
                print("Error checking video transform: \(error.localizedDescription)")
            }
        }
        
        // Check player item status periodically
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.checkPlayerStatus(playerItem: playerItem)
        }
        
        // Observe player item status
        statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
            DispatchQueue.main.async {
                self.checkPlayerStatus(playerItem: item)
            }
        }
        
        // Add observer for playback failure
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("ERROR: Video playback failed: \(error.localizedDescription)")
                self.playerError = error.localizedDescription
            }
        }
        
        player?.play()
        isPlaying = true
        
        // Set up notification observer for when video ends
        if let player = player {
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                isPlaying = false
            }
        }
    }
    
    private func checkPlayerStatus(playerItem: AVPlayerItem) {
        switch playerItem.status {
        case .readyToPlay:
            print("Video player ready to play")
            playerError = nil
        case .failed:
            let errorMsg = playerItem.error?.localizedDescription ?? "Unknown error"
            print("ERROR: Video player failed - \(errorMsg)")
            playerError = errorMsg
        case .unknown:
            print("Video player status unknown")
            // Check again after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkPlayerStatus(playerItem: playerItem)
            }
        @unknown default:
            break
        }
    }
    
    // MARK: - Upload
    @StateObject private var apiService = APIService.shared
    
    private func uploadData() {
        uploadStatus = nil
        uploadError = nil
        
        guard let depthURL = depthURL else {
            uploadError = "Depth JSON not found."
            return
        }
        
        isUploading = true
        
        apiService.uploadFiles(videoURL: videoURL, jsonURL: depthURL) { result in
            DispatchQueue.main.async {
                isUploading = false
                
                switch result {
                case .success(let responseString):
                    uploadStatus = "Uploaded successfully: \(responseString)"
                    print("📥 API Response: \(responseString)")
                    serverMessage = "success"
                    // Delete all files after successful upload
                    self.deleteRecordingFiles()
                    
                 /*   // Parse response to extract .obj file URL
                    var foundObjURL = false
                    
                    // Try parsing from response string first
                    if let objURL = apiService.parseObjURL(from: responseString) {
                        print("✅ Found OBJ URL in response: \(objURL.absoluteString)")
                        self.downloadObjFile(from: objURL)
                        foundObjURL = true
                    } else {
                        // Try parsing from JSON data if available
                        if let responseData = responseString.data(using: .utf8),
                           let objURL = apiService.extractObjURL(from: responseData) {
                            print("✅ Found OBJ URL in JSON: \(objURL.absoluteString)")
                            self.downloadObjFile(from: objURL)
                            foundObjURL = true
                        }
                    }
                    
                    if !foundObjURL {
                        print("⚠️ No OBJ file URL found in API response")
                        print("📄 Full response: \(responseString)")
                        uploadStatus = (uploadStatus ?? "Uploaded successfully.") + " (No 3D model URL in response)"
                    }*/
                    
                case .failure(let error):
                    serverMessage = "error"
                    uploadError = "Upload failed: \(error.localizedDescription)"
                    print("❌ Upload error: \(error.localizedDescription)")
                }
                showAlert = true
            }
        }
    }
    
    
    
    // MARK: - OBJ File Handling
    
    /// Check for existing .obj file in Documents directory (matching video file name)
    private func checkForExistingObjFile() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoFileName = videoURL.deletingPathExtension().lastPathComponent
        
        print("🔍 Checking for existing .obj files...")
        print("📁 Documents path: \(documentsPath.path)")
        print("🎥 Video file name: \(videoFileName)")
        
        // Check for .obj file with same base name as video
        let objFileName = "\(videoFileName).obj"
        let objFileURL = documentsPath.appendingPathComponent(objFileName)
        
        if FileManager.default.fileExists(atPath: objFileURL.path) {
            self.objFileURL = objFileURL
            print("✅ Found existing 3D model file: \(objFileURL.path)")
        } else {
            // Also check for any .obj file that might have been downloaded
            do {
                let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
                print("📋 Files in Documents directory:")
                for file in files {
                    print("   - \(file.lastPathComponent)")
                }
                
                if let objFile = files.first(where: { $0.pathExtension.lowercased() == "obj" }) {
                    self.objFileURL = objFile
                    print("✅ Found 3D model file: \(objFile.path)")
                } else {
                    print("❌ No .obj files found in Documents directory")
                }
            } catch {
                print("❌ Could not check for existing .obj files: \(error.localizedDescription)")
            }
        }
    }
    
    /// Delete all files related to this recording (video, JSON, depth maps, frame images)
    private func deleteRecordingFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoFileName = videoURL.deletingPathExtension().lastPathComponent
        let baseName = videoFileName
        
        print("🗑️ Deleting all files for recording: \(baseName)")
        
        do {
            // Delete video file
            if FileManager.default.fileExists(atPath: videoURL.path) {
                try FileManager.default.removeItem(at: videoURL)
                print("✅ Deleted video: \(videoURL.lastPathComponent)")
            }
            
            // Delete JSON file
            if let depthURL = depthURL, FileManager.default.fileExists(atPath: depthURL.path) {
                try FileManager.default.removeItem(at: depthURL)
                print("✅ Deleted JSON: \(depthURL.lastPathComponent)")
            }
            
            // Delete all frame images and depth maps with the same base name
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            
            let frameImageFiles = fileURLs.filter { url in
                let fileName = url.lastPathComponent
                return url.pathExtension.lowercased() == "jpg" && 
                       fileName.hasPrefix("\(baseName)_frame_")
            }
            
            let depthMapFiles = fileURLs.filter { url in
                let fileName = url.lastPathComponent
                return url.pathExtension.lowercased() == "bin" && 
                       fileName.hasPrefix("\(baseName)_depth_")
            }
            
            for frameFile in frameImageFiles {
                try? FileManager.default.removeItem(at: frameFile)
                print("✅ Deleted frame image: \(frameFile.lastPathComponent)")
            }
            
            for depthFile in depthMapFiles {
                try? FileManager.default.removeItem(at: depthFile)
                print("✅ Deleted depth map: \(depthFile.lastPathComponent)")
            }
            
            print("✅ Deleted \(frameImageFiles.count) frame image(s) and \(depthMapFiles.count) depth map(s)")
        } catch {
            print("⚠️ Error deleting files: \(error.localizedDescription)")
        }
    }
    
    
    /// Download .obj file from server
    private func downloadObjFile(from url: URL) {
        print("📥 Starting download of OBJ file from: \(url.absoluteString)")
        isDownloadingModel = true
        
        let session = URLSession.shared
        let task = session.downloadTask(with: url) { localURL, response, error in
            DispatchQueue.main.async {
                self.isDownloadingModel = false
                
                if let error = error {
                    self.uploadError = "Failed to download 3D model: \(error.localizedDescription)"
                    return
                }
                
                guard let localURL = localURL else {
                    let errorMsg = "No file received from server"
                    print("❌ \(errorMsg)")
                    self.uploadError = errorMsg
                    return
                }
                
                print("✅ File downloaded to temp location: \(localURL.path)")
                
                // Move downloaded file to Documents directory
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileName = url.lastPathComponent.isEmpty ? "model_\(UUID().uuidString).obj" : url.lastPathComponent
                let destinationURL = documentsPath.appendingPathComponent(fileName)
                
                print("📁 Moving file to: \(destinationURL.path)")
                
                do {
                    // Remove existing file if any
                    try? FileManager.default.removeItem(at: destinationURL)
                    // Move downloaded file
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)
                    
                    // Verify file exists
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
                        print("✅ 3D model saved successfully!")
                        print("   Path: \(destinationURL.path)")
                        print("   Size: \(fileSize) bytes")
                        
                        self.objFileURL = destinationURL
                       // self.uploadStatus = (self.uploadStatus ?? "Uploaded successfully.") + " 3D model downloaded!"
                    } else {
                        print("❌ File move failed - file not found at destination")
                       // self.uploadError = "Failed to save 3D model: File not found after move"
                    }
                } catch {
                    let errorMsg = "Failed to save 3D model: \(error.localizedDescription)"
                    print("❌ \(errorMsg)")
                    self.uploadError = errorMsg
                }
            }
        }
        
        task.resume()
    }
}

// Custom Video Player View that locks orientation and rotates video
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> PortraitLockedPlayerViewController {
        let controller = PortraitLockedPlayerViewController()
        controller.player = player
        
       // controller.showsPlaybackControls = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PortraitLockedPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

class PortraitLockedPlayerViewController: AVPlayerViewController {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    override var shouldAutorotate: Bool {
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // AVPlayerViewController already handles orientation
        videoGravity = .resizeAspect
        showsPlaybackControls = true
    }
}

//class PortraitLockedPlayerViewController: AVPlayerViewController {
//    private var playerLayer: AVPlayerLayer?
//    
//    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
//        return .portrait
//    }
//    
//    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
//        return .portrait
//    }
//    
//    override var shouldAutorotate: Bool {
//        return false
//    }
//    
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        videoGravity = .resizeAspect
//        showsPlaybackControls = false
//        
//        // Setup custom player layer with rotation
//        setupRotatedPlayerLayer()
//    }
//    
//    override func viewDidLayoutSubviews() {
//        super.viewDidLayoutSubviews()
//        playerLayer?.frame = view.bounds
//    }
//    
//    private func setupRotatedPlayerLayer() {
//        guard let player = player, let playerItem = player.currentItem else { return }
//        
//        // Remove existing player layer if any
//        view.layer.sublayers?.forEach { if $0 is AVPlayerLayer { $0.removeFromSuperlayer() } }
//        
//        // Check video orientation
//        let asset = playerItem.asset
//        let videoTracks = asset.tracks(withMediaType: .video)
//        
//        guard let videoTrack = videoTracks.first else { return }
//        
//        let naturalSize = videoTrack.naturalSize
//        let transform = videoTrack.preferredTransform
//        
//        // Determine if video is portrait (height > width) or if transform indicates rotation needed
//        let isPortraitVideo = naturalSize.height > naturalSize.width
//        
//        // Create new player layer
//        let layer = AVPlayerLayer(player: player)
//        layer.videoGravity = .resizeAspect
//        
//        if isPortraitVideo {
//            // Rotate 90 degrees clockwise to fix portrait video playing in landscape
//            layer.transform = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)
//            
//            // Adjust frame after rotation
//            let rotatedSize = CGSize(width: view.bounds.height, height: view.bounds.width)
//            layer.frame = CGRect(
//                x: (view.bounds.width - rotatedSize.width) / 2,
//                y: (view.bounds.height - rotatedSize.height) / 2,
//                width: rotatedSize.width,
//                height: rotatedSize.height
//            )
//        } else {
//            // No rotation needed, use normal frame
//            layer.frame = view.bounds
//        }
//        
//        view.layer.addSublayer(layer)
//        playerLayer = layer
//    }
//    
//    override var player: AVPlayer? {
//        didSet {
//            setupRotatedPlayerLayer()
//        }
//    }
//}

#Preview {
    // Preview with a placeholder URL
    VideoPlaybackView(videoURL: URL(fileURLWithPath: ""), depthURL: nil)
}

