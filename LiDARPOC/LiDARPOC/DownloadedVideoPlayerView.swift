//
//  DownloadedVideoPlayerView.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI
import AVKit
import AVFoundation
class DownloadedViewPlayerViewModel: ObservableObject {
    @Published var capturedImage: UIImage?

}
struct DownloadedVideoPlayerView: View {
    @Environment(\.dismiss) var dismiss
    let videoURL: URL?
    let fileId: String?
    @StateObject var viewModel: DownloadedViewPlayerViewModel = DownloadedViewPlayerViewModel()
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playerError: String?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadedVideoURL: URL?
    @State private var show2DViewer = false
    
    // Overlay controls (same behavior as VideoPlaybackView)
    @State private var timeObserverToken: Any?
    @State private var currentTimeSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var showOverlayControls = true
    @State private var overlayAutoHideWorkItem: DispatchWorkItem?
    
    @StateObject private var apiService = APIService.shared
    
    init(videoURL: URL? = nil, fileId: String? = nil) {
        self.videoURL = videoURL
        self.fileId = fileId
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Fullscreen video / error / loading
            Group {
                if isDownloading {
                    VStack(spacing: 20) {
                        ProgressView(value: downloadProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                            .frame(width: 220)
                        Text("Downloading video... \(Int(downloadProgress * 100))%")
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let player = player, playerError == nil {
                    ZStack {
                        // Reuse the same player used in VideoPlaybackView (rotates preview if needed)
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
                                Button(action: {
                                    togglePlayPause()
                                }) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 78))
                                        .foregroundColor(.white)
                                        .shadow(radius: 10)
                                }
                                
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
                                                set: { newValue in currentTimeSeconds = newValue }
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
            
            // Top chrome (close + capture)
            VStack {
                HStack {
                    Button(action: {
                        player?.pause()
                        isPlaying = false
                        dismiss()
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
                    
                    if !isDownloading, player != nil, playerError == nil {
                        Button(action: {
                            captureFrameFromVideo()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Capture")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.90))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .shadow(radius: 6)
                        }
                        .padding(.trailing, 16)
                        .padding(.vertical, 10)
                    }
                }
                .padding(.top, 44)
                
                Spacer()
            }
        }
        .onAppear {
            if let fileId = fileId, downloadedVideoURL == nil {
                downloadVideo()
            } else if let url = effectiveVideoURL {
                setupPlayer(url: url)
            }
        }
        .onDisappear {
            // Ensure auto-lock is re-enabled when leaving the view
            UIApplication.shared.isIdleTimerDisabled = false
            statusObserver?.invalidate()
            statusObserver = nil
            removeTimeObserver()
            overlayAutoHideWorkItem?.cancel()
            overlayAutoHideWorkItem = nil
            player?.pause()
            player = nil
        }
        .fullScreenCover(isPresented: $show2DViewer) {
            if let image = viewModel.capturedImage, let fileId = fileId {
                Model2DViewerView(image: image, fileId: fileId)
            } else {
                // Debugging fallback
                VStack {
                    Text("Error: Missing Data")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("Captured Image: \(viewModel.capturedImage != nil ? "Present" : "Nil")")
                    Text("File ID: \(fileId != nil ? "Present" : "Nil")")
                    Button("Close") {
                        show2DViewer = false
                    }
                }
                .onAppear {
                    print("⚠️ fullScreenCover - Image: \(viewModel.capturedImage != nil), FileID: \(fileId != nil)")
                }
            }
        }
    }
   
    
    private var effectiveVideoURL: URL? {
        downloadedVideoURL ?? videoURL
    }
    
    private func downloadVideo() {
        guard let fileId = fileId else { return }
        
        isDownloading = true
        playerError = nil
        downloadProgress = 0.0
        
        // Disable auto-lock while downloading
        UIApplication.shared.isIdleTimerDisabled = true
        
        apiService.downloadFile(fileId: fileId, fileType: "video", progress: { progress in
            self.downloadProgress = progress
        }) { result in
            DispatchQueue.main.async {
                isDownloading = false
                // Re-enable auto-lock
                UIApplication.shared.isIdleTimerDisabled = false
                
                switch result {
                case .success(let url):
                    downloadedVideoURL = url
                    setupPlayer(url: url)
                    
                case .failure(let error):
                    playerError = "Failed to download video: \(error.localizedDescription)"
                    print("Error downloading video: \(error.localizedDescription)")
                }
            }
        }
    }
        
    private func captureFrameFromVideo() {
        print("📸 Starting frame capture...")
        guard let player = player, let currentItem = player.currentItem else { 
            print("❌ Player or item missing")
            return 
        }
        
        let currentTime = player.currentTime()
        print("⏱️ Time: \(currentTime.seconds)")
        let asset = currentItem.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        Task {
            do {
                print("⏳ Generating image...")
                let (cgImage, actualTime) = try await generator.image(at: currentTime)
                print("✅ Image generated at \(actualTime.seconds)")
                
                var uiImage = UIImage(cgImage: cgImage)
                
                // Match the on-screen orientation:
                // Our shared VideoPlayerView rotates the preview when the encoded video is landscape but UI is portrait.
                // In that case, rotate the captured frame too (so Model2DViewerView gets the same orientation).
                if shouldRotateCaptureToMatchPortraitPreview(asset: asset) {
                    uiImage = rotateImage90DegreesClockwise(uiImage) ?? uiImage
                }
                print("🖼️ UIImage created: \(uiImage.size)")
                
                await MainActor.run {
                    print("💾 Setting state: capturedImage = \(uiImage)")
                    self.viewModel.capturedImage = uiImage
                    
                    // Verify it was set
                    if self.viewModel.capturedImage != nil {
                         print("✅ capturedImage set successfully")
                         print("💾 Setting state: show2DViewer")
                         self.show2DViewer = true
                         player.pause()
                         self.isPlaying = false
                    } else {
                         print("❌ Failed to set capturedImage (it is nil after assignment?)")
                    }
                }
            } catch {
                print("❌ Error capturing frame: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupPlayer(url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        isPlaying = false
        currentTimeSeconds = 0
        durationSeconds = 0
        
        // Observe player item status
        statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
            DispatchQueue.main.async {
                checkPlayerStatus(playerItem: item)
            }
        }
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak newPlayer] _ in
            guard let player = newPlayer else { return }
            player.seek(to: .zero)
            isPlaying = false
            currentTimeSeconds = 0
            withAnimation(.easeInOut(duration: 0.15)) {
                showOverlayControls = true
            }
        }
        
        // Observe playback errors
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
    }
    
    private func checkPlayerStatus(playerItem: AVPlayerItem) {
        switch playerItem.status {
        case .readyToPlay:
            print("Video player ready to play")
            playerError = nil
            updateDuration()
            startTimeObserverIfNeeded()
        case .failed:
            if let error = playerItem.error {
                print("ERROR: Player item failed: \(error.localizedDescription)")
                playerError = error.localizedDescription
            }
        case .unknown:
            print("Player item status unknown")
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
    
    // MARK: - Capture orientation helpers
    
    private func shouldRotateCaptureToMatchPortraitPreview(asset: AVAsset) -> Bool {
        guard let track = asset.tracks(withMediaType: .video).first else { return false }
        let transformedSize = track.naturalSize.applying(track.preferredTransform)
        let w = abs(transformedSize.width)
        let h = abs(transformedSize.height)
        
        // Same heuristic as RotatingPlayerViewController:
        // if the *encoded* video is landscape, preview rotates in portrait UI.
        return w > h
    }
    
    private func rotateImage90DegreesClockwise(_ image: UIImage) -> UIImage? {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            ctx.cgContext.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

