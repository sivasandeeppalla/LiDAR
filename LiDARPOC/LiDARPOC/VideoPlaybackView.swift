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
    @State private var timeObserverToken: Any?
    @State private var currentTimeSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var showOverlayControls = true
    @State private var overlayAutoHideWorkItem: DispatchWorkItem?
    
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
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

            // Fullscreen video / error / loading
            Group {
                if let player = player, playerError == nil {
                    ZStack {
                        VideoPlayerView(player: player)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showOverlayControls.toggle()
                                }
                                if showOverlayControls {
                                    scheduleOverlayAutoHide()
                                }
                            }

                        // Overlay controls (center play/pause + bottom scrubber)
                        if showOverlayControls {
                            ZStack {
                                // Center play/pause
                                Button(action: {
                                    togglePlayPause()
                                }) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 78))
                                        .foregroundColor(.white)
                                        .shadow(radius: 10)
                                }

                                // Bottom scrub bar
                                VStack {
                                    Spacer()

                                    VStack(spacing: 10) {
                                        HStack {
                                            Text(formatTime(currentTimeSeconds))
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.95))

                                            Spacer()

                                            Text(formatTime(durationSeconds))
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.95))
                                        }

                                        Slider(
                                            value: Binding(
                                                get: { min(max(currentTimeSeconds, 0), max(durationSeconds, 0)) },
                                                set: { newValue in
                                                    currentTimeSeconds = newValue
                                                }
                                            ),
                                            in: 0...(durationSeconds > 0 ? durationSeconds : 1)
                                        ) { editing in
                                            handleScrub(editing: editing)
                                        }
                                        .tint(.white)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.black.opacity(0.60))
                                    .cornerRadius(14)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 22)
                                }
                            }
                            .transition(.opacity)
                            .onAppear {
                                scheduleOverlayAutoHide()
                            }
                        }
                    }
                } else if let error = playerError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Error loading video")
                            .foregroundColor(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Top/Bottom chrome
            VStack {
                // Top bar with close + upload
                HStack {
                    Button(action: {
                        player?.pause()
                        dismiss()
                        close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 10)

                    Spacer()

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
                        .background(isUploading ? Color.blue.opacity(0.45) : Color.blue.opacity(0.90))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(radius: 6)
                    }
                    .padding(.trailing, 16)
                    .padding(.vertical, 10)
                    .disabled(isUploading)
                }
                .padding(.top, 44)

                Spacer()

                if isUploading {
                    VStack(spacing: 8) {
                        ProgressView(value: uploadProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .frame(maxWidth: 240)
                        Text("Uploading… \(Int(uploadProgress * 100))%")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
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
            removeTimeObserver()
            overlayAutoHideWorkItem?.cancel()
            overlayAutoHideWorkItem = nil
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
        isPlaying = false
        
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
        startTimeObserverIfNeeded()
        
        // Set up notification observer for when video ends
        if let player = player {
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                isPlaying = false
                currentTimeSeconds = 0
                withAnimation(.easeInOut(duration: 0.15)) {
                    showOverlayControls = true
                }
            }
        }
    }
    
    private func checkPlayerStatus(playerItem: AVPlayerItem) {
        switch playerItem.status {
        case .readyToPlay:
            print("Video player ready to play")
            playerError = nil
            updateDuration()
            startTimeObserverIfNeeded()
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
    
    // MARK: - Overlay controls helpers
    
    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        scheduleOverlayAutoHide()
    }
    
    private func scheduleOverlayAutoHide() {
        overlayAutoHideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            DispatchQueue.main.async {
                // Only auto-hide if actively playing and not scrubbing.
                if isPlaying && !isScrubbing {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showOverlayControls = false
                    }
                }
            }
        }
        overlayAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    private func handleScrub(editing: Bool) {
        guard let player = player else { return }
        if editing {
            isScrubbing = true
            wasPlayingBeforeScrub = isPlaying
            player.pause()
            isPlaying = false
            overlayAutoHideWorkItem?.cancel()
        } else {
            let target = CMTime(seconds: currentTimeSeconds, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if wasPlayingBeforeScrub {
                    player.play()
                    isPlaying = true
                }
                isScrubbing = false
                scheduleOverlayAutoHide()
            }
        }
    }
    
    private func startTimeObserverIfNeeded() {
        guard timeObserverToken == nil, let player = player else { return }
        
        // Update 4x per second for smooth scrub UI
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                currentTimeSeconds = seconds
            }
            updateDuration()
        }
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
    }
    
    private func updateDuration() {
        guard let item = player?.currentItem else { return }
        let d = CMTimeGetSeconds(item.duration)
        if d.isFinite && d > 0 {
            durationSeconds = d
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    // MARK: - Upload
    @StateObject private var apiService = APIService.shared
    
    private func uploadData() {
        uploadStatus = nil
        uploadError = nil
        uploadProgress = 0.0
        
        guard let depthURL = depthURL else {
            uploadError = "Depth JSON not found."
            return
        }
        
        isUploading = true
        
        apiService.uploadFiles(videoURL: videoURL, jsonURL: depthURL, progress: { progress in
            self.uploadProgress = progress
        }) { result in
            DispatchQueue.main.async {
                isUploading = false
                
                switch result {
                case .success(let responseString):
                    uploadStatus = "Uploaded successfully: \(responseString)"
                    print("📥 API Response: \(responseString)")
                    serverMessage = "success"
                    uploadProgress = 1.0
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

// Custom Video Player View:
// - Keeps the app UI in portrait
// - Rotates ONLY the preview layer when the *encoded* video is landscape
// - Does NOT modify the recorded file (upload stays consistent with depth/intrinsics)
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> RotatingPlayerViewController {
        let controller = RotatingPlayerViewController()
        controller.player = player
        return controller
    }
    
    func updateUIViewController(_ uiViewController: RotatingPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

final class RotatingPlayerViewController: UIViewController {
    private let playerLayer = AVPlayerLayer()
    
    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
            updateLayerLayoutAndRotation()
        }
    }

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
        view.backgroundColor = .black
        
        // Fill the screen (cropping a bit is preferable to huge black bars)
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayerLayoutAndRotation()
    }
    
    private func updateLayerLayoutAndRotation() {
        let viewBounds = view.bounds
        guard viewBounds.width > 0, viewBounds.height > 0 else { return }
        
        // Default: no rotation
        var shouldRotateForPortraitPreview = false
        
        if let asset = player?.currentItem?.asset,
           let track = asset.tracks(withMediaType: .video).first {
            let naturalSize = track.naturalSize
            let preferredTransform = track.preferredTransform
            let transformedSize = naturalSize.applying(preferredTransform)
            
            let w = abs(transformedSize.width)
            let h = abs(transformedSize.height)
            
            // If the encoded video is landscape but UI is portrait, rotate the preview.
            if w > h && viewBounds.height > viewBounds.width {
                shouldRotateForPortraitPreview = true
            }
        }
        
        if shouldRotateForPortraitPreview {
            // Use bounds+position so rotation stays centered and fills the view.
            playerLayer.bounds = CGRect(origin: .zero, size: CGSize(width: viewBounds.height, height: viewBounds.width))
            playerLayer.position = CGPoint(x: viewBounds.midX, y: viewBounds.midY)
            playerLayer.transform = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)
        } else {
            playerLayer.transform = CATransform3DIdentity
            playerLayer.frame = viewBounds
        }
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

