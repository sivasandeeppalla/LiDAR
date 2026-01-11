//
//  CameraRecordView.swift
//  LiDARPOC
//
//  Created by Siva Sandeep on 13/12/25.
//

import SwiftUI
import ARKit
import AVFoundation
import AVKit
import ReplayKit
import CoreImage

struct CameraRecordView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var cameraManager = CameraManager()
    @State private var recordedVideoURL: URL?
    @State private var depthDataURL: URL?
    @State private var showTutorial = false
    @State private var tutorialVisible = false
    @State private var showAnimationVideo = false
    @State private var animationPlayer: AVPlayer?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // AR Preview
            ARViewRepresentable(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            VStack {
                // Top bar with close button
                VStack {
                    HStack {
                        Spacer()
                        
                        // Timer (center)
                        if cameraManager.isRecording {
                            Text(cameraManager.timerString)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.7))
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        // Close button (top-right)
                        Button(action: {
                            if cameraManager.isRecording {
                                cameraManager.stopRecording { url, depthURL in
                                    DispatchQueue.main.async {
                                        if let url = url {
                                            recordedVideoURL = url
                                            depthDataURL = depthURL
                                        }
                                    }
                                }
                            }
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 50) // Safe top spacing
                    Spacer() // pushes content to top
                }
                Spacer()
                // Record button
                Button(action: {
                    if cameraManager.isRecording {
                        cameraManager.stopRecording { url, depthURL in
                            DispatchQueue.main.async {
                                if let url = url {
                                    print("Recording stopped, video URL: \(url.path)")
                                    let fileExists = FileManager.default.fileExists(atPath: url.path)
                                    print("Video file exists: \(fileExists)")
                                    if fileExists {
                                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                                        print("Video file size: \(fileSize) bytes")
                                        recordedVideoURL = url
                                        depthDataURL = depthURL
                                    } else {
                                        print("ERROR: Video file does not exist!")
                                    }
                                } else {
                                    print("ERROR: No video URL returned from recording")
                                }
                            }
                        }
                    } else {
                        cameraManager.startRecording()
                        // Show tutorial when recording starts
                        showTutorial = true
                        tutorialVisible = true
                        // Tutorial will auto-dismiss after 5 seconds (handled in TutorialOverlayView)
                        // Remove tutorial view after fade out completes
                        showTutorial = false
                        // Show animation video after tutorial dismisses
                        showAnimationVideo = true
                        // Auto-dismiss animation after 5.5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showAnimationVideo = false
                            }
                            animationPlayer?.pause()
                            animationPlayer = nil
                        }
                        
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(cameraManager.isRecording ? Color.red : Color.white)
                            .frame(width: 80, height: 80)
                        
                        if !cameraManager.isRecording {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 70, height: 70)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            
            
            // Bottom controls with guidance overlays
            VStack(spacing: 20) {
                // Guidance overlays - all in same position
                VStack(spacing: 12) {
                    // Lighting warning
                    if let warning = cameraManager.lightingWarning {
                        Text(warning)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                    
                    // Animation video (only show when recording and tutorial is dismissed)
                    // Rotation instruction (only show when recording and tutorial is dismissed)
                    
                    if cameraManager.isRecording && !showTutorial  {
                        
                        if let url = getAnimationUrl(),showAnimationVideo {
                            VStack {
                                Spacer()
                                TutorialVideoView(url: url, isInReviewSheet: false)
                                    .frame(maxHeight: 280)
                                    .overlay(alignment: .bottom) {
                                        Text("Please rotate the device around the object")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(8)
                                            .transition(.opacity)
                                    }
                                Spacer()
                            }
                            .background(Color.black.opacity(0.5))
                            .allowsHitTesting(false)
                        }
                        
                        
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(item: $recordedVideoURL) { videoURL in
            VideoPlaybackView(videoURL: videoURL, depthURL: depthDataURL) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.000000001, execute: {
                    dismiss()
                })
            }
        }
        .onAppear {
            cameraManager.setupARSession()
        }
        .onDisappear {
            // Stop ARSession completely when view disappears
            print("CameraRecordView onDisappear - stopping ARSession")
            cameraManager.stopARSession()
            // Clean up animation player
            animationPlayer?.pause()
            animationPlayer = nil
        }
        .animation(.easeInOut, value: cameraManager.lightingWarning)
        .animation(.easeInOut, value: cameraManager.isRecording)
        .animation(.easeInOut, value: showAnimationVideo)
    }
    
    private func getAnimationUrl() -> URL? {
        // Load animation video from bundle - try multiple paths
        var videoURL: URL?
        
        // First try with subdirectory
        videoURL = Bundle.main.url(forResource: "animation", withExtension: "mp4", subdirectory: "Resources")
        
        // If not found, try without subdirectory
        if videoURL == nil {
            videoURL = Bundle.main.url(forResource: "animation", withExtension: "mp4")
        }
        
        guard let url = videoURL else {
            print("ERROR: Could not find animation.mp4 in bundle")
            return nil
        }
        return url
//        let player = AVPlayer(url: url)
//        player.isMuted = true
//        player.play()
//        
//        // Loop the video
//        NotificationCenter.default.addObserver(
//            forName: .AVPlayerItemDidPlayToEndTime,
//            object: player.currentItem,
//            queue: .main
//        ) { _ in
//            player.seek(to: .zero)
//            player.play()
//        }
//        
//        animationPlayer = player
    }
}

// AR Camera Manager
class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var timerString = "00:00"
    @Published var lightingWarning: String? = nil
    @Published var scanningProgress: Float = 0.0
    @Published var rotationAngle: Float = 0.0
    
    var arSession: ARSession?
    
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var depthFrames: [DepthFrameData] = []
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var frameCount: Int = 0
    private var totalFrameCount: Int = 0  // For logging
    private var recordingQueue = DispatchQueue(label: "recording.queue")
    private var videoOutputURL: URL?
    private var isWriterSetup = false
    private var recordingBaseName: String?
    private var sourceWidth: Int = 0
    private var sourceHeight: Int = 0
    private let targetWidth: Int = 1280  // Video and image resolution
    private let targetHeight: Int = 960  // Video and image resolution
    private let depthTargetWidth: Int = 256  // Low resolution for depth maps to save memory
    private let depthTargetHeight: Int = 192  // Low resolution for depth maps to save memory
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    override init() {
        super.init()
    }
    
    func setupARSession() {
        // If session exists but is paused, resume it
        if let session = arSession {
            if session.delegate == nil {
                session.delegate = self
            }
            if session.configuration == nil {
                let configuration = createARConfiguration()
                session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            }
            return
        }
        
        let session = ARSession()
        
        let configuration = createARConfiguration()
        
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        self.arSession = session
        print("ARSession started with frame semantics: \(configuration.frameSemantics)")
    }
    
    private func createARConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        
        // Check if device supports scene depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
            print("Enabled sceneDepth frame semantics")
        }
        
        // Also try smoothed scene depth if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
            print("Enabled smoothedSceneDepth frame semantics")
        }
        
        return configuration
    }
    
    func stopARSession() {
        print("Stopping ARSession completely")
        isRecording = false
        arSession?.pause()
        arSession?.delegate = nil  // Remove delegate to stop receiving updates
        // Clear the session reference
        arSession = nil
        print("ARSession stopped and delegate removed")
    }
    
    func pauseARSession() {
        stopARSession()
    }
    
    func startRecording() {
        guard !isRecording else { return }
        guard let session = arSession else {
            print("ERROR: ARSession is nil, cannot start recording")
            return
        }
        
        // Reset all recording state BEFORE starting
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Clean up any existing writer
            if let writer = self.assetWriter, writer.status == .writing {
                self.videoInput?.markAsFinished()
                writer.finishWriting { }
            }
            
            // Reset writer state
            self.assetWriter = nil
            self.videoInput = nil
            self.pixelBufferAdaptor = nil
            self.isWriterSetup = false
            self.videoOutputURL = nil
            self.recordingBaseName = nil
            
            DispatchQueue.main.async {
            // Clear all recording data
            self.depthFrames.removeAll()
            self.frameCount = 0
            self.totalFrameCount = 0
            self.cameraPositions.removeAll()
            self.lastCameraPosition = nil
            self.scanningProgress = 0.0
            self.isRecording = true
            self.recordingStartTime = Date()
            self.startTimer()
            
            print("✅ Recording started - writer will be setup on first frame")
            }
        }
    }
    
    func stopRecording(completion: @escaping (URL?, URL?) -> Void) {
        guard isRecording else {
            completion(nil, nil)
            return
        }
        
        isRecording = false
        stopTimer()
        
        recordingQueue.async { [weak self] in
            guard let self = self else {
                completion(nil, nil)
                return
            }
            
            // Finish video writing
            guard let writer = self.assetWriter, writer.status == .writing else {
                print("ERROR: Writer not in writing state: \(self.assetWriter?.status.rawValue ?? -1)")
                let videoURL = self.videoOutputURL
                let depthURL = self.saveDepthData()
                
                DispatchQueue.main.async {
                    completion(videoURL, depthURL)
                }
                return
            }
            
            self.videoInput?.markAsFinished()
            writer.finishWriting { [weak self] in
                guard let self = self else { return }
                
                if writer.status == .completed {
                    print("Video recording completed successfully")
                } else if writer.status == .failed {
                    print("ERROR: Video recording failed - \(writer.error?.localizedDescription ?? "unknown")")
                }
                
                let videoURL = self.videoOutputURL
                
                // Save depth data
                let depthURL = self.saveDepthData()
                
                // Reset writer state
                self.assetWriter = nil
                self.videoInput = nil
                self.pixelBufferAdaptor = nil
                self.isWriterSetup = false
                
                DispatchQueue.main.async {
                    completion(videoURL, depthURL)
                }
            }
        }
    }
    
    private func setupVideoWriter(for pixelBuffer: CVPixelBuffer, outputURL: URL) -> Bool {
        // Get actual dimensions from the pixel buffer (source resolution)
        sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        print("Source frame dimensions: \(sourceWidth)x\(sourceHeight), format: \(pixelFormat)")
        print("Target video output dimensions: \(targetWidth)x\(targetHeight)")
        
        do {
            // Remove file if exists
            try? FileManager.default.removeItem(at: outputURL)
            
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            // Always output at target resolution (1280x960 - memory-efficient)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: targetWidth,
                AVVideoHeightKey: targetHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8000000  // Bitrate for 1280x960 resolution (8 Mbps)
                ]
            ]
            
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            // ✅ THIS IS MANDATORY FOR PORTRAIT
            input.transform = CGAffineTransform(rotationAngle: .pi / 2)

            input.expectsMediaDataInRealTime = true
            
            // Use kCVPixelFormatType_32BGRA for output (standard RGB format)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: targetWidth,
                    kCVPixelBufferHeightKey as String: targetHeight,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ]
            )
            
            guard writer.canAdd(input) else {
                print("ERROR: Cannot add video input to writer")
                return false
            }
            
            writer.add(input)
            
            guard writer.startWriting() else {
                print("ERROR: Cannot start writing - \(writer.error?.localizedDescription ?? "unknown error")")
                return false
            }
            
            writer.startSession(atSourceTime: .zero)
            
            self.assetWriter = writer
            self.videoInput = input
            self.pixelBufferAdaptor = adaptor
            self.videoOutputURL = outputURL
            self.isWriterSetup = true
            
            print("✅ Video writer setup successful")
            print("   Source resolution: \(sourceWidth)x\(sourceHeight)")
            print("   Target output resolution: \(targetWidth)x\(targetHeight)")
            print("   Upscaling: \(sourceWidth != targetWidth || sourceHeight != targetHeight ? "YES" : "NO")")
            return true
        } catch {
            print("ERROR: Error setting up video writer: \(error.localizedDescription)")
            return false
        }
    }
    
    private func processFrame(_ frame: ARFrame) {
        // Double check we're actually recording
        guard isRecording else { 
            return 
        }
        
        recordingQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            
            // NOTE: Each call to processFrame() receives a NEW, SEPARATE frame
            // frame.capturedImage is a CVPixelBuffer containing ONE camera image frame
            // This method is called ~30-60 times per second (once per frame)
            let capturedImage = frame.capturedImage
            
            // Setup writer on first frame AFTER recording starts
            if !self.isWriterSetup {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                // Use same base name for video and JSON
                let baseName = UUID().uuidString
                self.recordingBaseName = baseName
                let videoPath = documentsPath.appendingPathComponent("\(baseName).mov")
                
                if !self.setupVideoWriter(for: capturedImage, outputURL: videoPath) {
                    print("ERROR: Failed to setup video writer, stopping recording")
                    DispatchQueue.main.async {
                        self.isRecording = false
                        self.stopTimer()
                    }
                    return
                }
            }
            
            // Capture depth data at low resolution (256x192) to save memory
            // Video/images remain at 1280x960
            // Depth maps are saved to files immediately to avoid memory accumulation
            if let baseName = self.recordingBaseName,
               let depthData = DepthDataManager.shared.depthDataFromARFrame(
                frame,
                targetWidth: self.depthTargetWidth,
                targetHeight: self.depthTargetHeight,
                videoWidth: self.targetWidth,
                videoHeight: self.targetHeight,
                baseName: baseName,
                frameNumber: self.totalFrameCount
            ) {
                self.depthFrames.append(depthData)
            } else {
                // Only log occasionally to avoid spam
                if self.frameCount % 30 == 0 {
                    print("Warning: Could not extract depth data from frame")
                }
            }
            
            // Write video frame from capturedImage
            guard let adaptor = self.pixelBufferAdaptor,
                  let input = self.videoInput,
                  let writer = self.assetWriter else {
                print("ERROR: Writer components not available")
                return
            }
            
            guard writer.status == .writing else {
                if writer.status == .failed {
                    print("ERROR: Writer failed - \(writer.error?.localizedDescription ?? "unknown")")
                    DispatchQueue.main.async {
                        self.isRecording = false
                        self.stopTimer()
                    }
                }
                return
            }
            
            guard input.isReadyForMoreMediaData else {
                // This is normal, just skip this frame
                return
            }
            
            let presentationTime = CMTime(value: Int64(self.frameCount), timescale: 30)
            
            // Upscale frame to target resolution if needed
            let outputBuffer = self.upscalePixelBuffer(capturedImage, toWidth: self.targetWidth, toHeight: self.targetHeight)
            
            guard let outputBuffer = outputBuffer else {
                print("ERROR: Failed to upscale pixel buffer at frame \(self.frameCount)")
                self.frameCount += 1
                return
            }
            
            // Append the upscaled image
            let success = adaptor.append(outputBuffer, withPresentationTime: presentationTime)
            if !success {
                print("ERROR: Failed to append pixel buffer at frame \(self.frameCount)")
            }
            
            self.frameCount += 1
        }
    }
    
    private func saveDepthData() -> URL? {
        guard !depthFrames.isEmpty else {
            print("No depth frames to save")
            return nil
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Use same base name as video
        let baseName = recordingBaseName ?? UUID().uuidString
        let depthPath = documentsPath.appendingPathComponent("\(baseName).json")
        
        DepthDataManager.shared.saveDepthFrames(depthFrames, to: depthPath)
        
        return depthPath
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            self.timerString = String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerString = "00:00"
        recordingStartTime = nil
    }
    
    // Upscale pixel buffer to target resolution using Core Image
    private func upscalePixelBuffer(_ inputBuffer: CVPixelBuffer, toWidth: Int, toHeight: Int) -> CVPixelBuffer? {
        // Check if upscaling is needed
        let inputWidth = CVPixelBufferGetWidth(inputBuffer)
        let inputHeight = CVPixelBufferGetHeight(inputBuffer)
        
        // Log upscaling info occasionally
        if self.frameCount % 60 == 0 {
            print("Upscaling frame: \(inputWidth)x\(inputHeight) -> \(toWidth)x\(toHeight)")
        }
        
        if inputWidth == toWidth && inputHeight == toHeight {
            // No upscaling needed, return original buffer converted to BGRA
            return convertToBGRA(inputBuffer)
        }
        
        // Create Core Image from pixel buffer
        let ciImage = CIImage(cvPixelBuffer: inputBuffer)
        
        // Create output pixel buffer pool
        let pixelBufferPool = createPixelBufferPool(width: toWidth, height: toHeight)
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &outputBuffer)
        
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            print("ERROR: Failed to create output pixel buffer for upscaling")
            return nil
        }
        
        // Lock the output buffer
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        
        // Render scaled image to output buffer
        let scaleTransform = CGAffineTransform(scaleX: CGFloat(toWidth) / CGFloat(inputWidth),
                                                y: CGFloat(toHeight) / CGFloat(inputHeight))
        let scaledImage = ciImage.transformed(by: scaleTransform)
        
        ciContext.render(scaledImage, to: output)
        
        return output
    }
    
    // Convert pixel buffer to BGRA format
    private func convertToBGRA(_ inputBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let inputWidth = CVPixelBufferGetWidth(inputBuffer)
        let inputHeight = CVPixelBufferGetHeight(inputBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(inputBuffer)
        
        // If already BGRA, return as-is
        if pixelFormat == kCVPixelFormatType_32BGRA {
            return inputBuffer
        }
        
        // Convert using Core Image
        let ciImage = CIImage(cvPixelBuffer: inputBuffer)
        
        let pixelBufferPool = createPixelBufferPool(width: inputWidth, height: inputHeight)
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &outputBuffer)
        
        guard status == kCVReturnSuccess, let output = outputBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        
        ciContext.render(ciImage, to: output)
        
        return output
    }
    
    // Create a reusable pixel buffer pool for better performance
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0
    
    // Guidance tracking
    private var lastCameraPosition: simd_float3?
    private var cameraPositions: [simd_float3] = []
    private var lightingCheckFrameCount: Int = 0
    
    private func createPixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool {
        // Reuse pool if dimensions match
        if let pool = pixelBufferPool, poolWidth == width && poolHeight == height {
            return pool
        }
        
        // Create new pool with target dimensions
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &pool)
        
        if status == kCVReturnSuccess, let createdPool = pool {
            pixelBufferPool = createdPool
            poolWidth = width
            poolHeight = height
            return createdPool
        }
        
        // Fallback: create a simple pool without IOSurface
        let fallbackAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        
        var fallbackPool: CVPixelBufferPool?
        let fallbackStatus = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, fallbackAttributes as CFDictionary, &fallbackPool)
        
        guard fallbackStatus == kCVReturnSuccess, let pool = fallbackPool else {
            fatalError("Failed to create pixel buffer pool")
        }
        
        pixelBufferPool = pool
        poolWidth = width
        poolHeight = height
        return pool
    }
}

extension CameraManager: ARSessionDelegate {
    // MARK: - ARSessionDelegate: Frame Access
    //
    // This method is called for EACH frame (~30-60fps) from ARKit
    // Each ARFrame contains:
    //   - frame.capturedImage: CVPixelBuffer (the actual camera image frame)
    //   - frame.timestamp: Time when frame was captured
    //   - frame.camera: Camera position, transform, intrinsics
    //   - frame.sceneDepth: Depth map (if available)
    //
    // WHERE TO ACCESS FRAMES:
    //   1. In this method: session(_:didUpdate:) - called for every frame
    //   2. In processFrame() - called when recording is active
    //   3. You can save frames using saveIndividualFrame() helper
    //   4. Convert to UIImage using pixelBufferToUIImage() helper
    //   5. Get frame info using getFrameInfo() helper
    //
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Only process if we still have a delegate (session is active)
        guard session.delegate != nil else {
            return
        }
        
        totalFrameCount += 1
        
        // Check lighting (every 30 frames to avoid performance impact)
        if totalFrameCount % 30 == 0 {
            checkLighting(frame: frame)
        }
        
        // Track camera movement for rotation guidance
        if isRecording {
            trackCameraMovement(frame: frame)
        }
        
        // Only log and process frames when recording
        if isRecording {
            // Log frame info periodically (not every frame to avoid spam)
            if totalFrameCount % 30 == 0 {
                print("\n=== ARFrame Info (Frame #\(totalFrameCount)) - RECORDING ===")
                
                // Use helper method to get frame info
                let frameInfo = getFrameInfo(frame)
                print("Frame Info: \(frameInfo)")
                
                // Access individual frame image
                let capturedImage = frame.capturedImage
                let width = CVPixelBufferGetWidth(capturedImage)
                let height = CVPixelBufferGetHeight(capturedImage)
                print("📸 CapturedImage: \(width)x\(height) pixels")
                print("⏱️ Timestamp: \(frame.timestamp)")
                
                // Camera transform and position
                print("📷 Camera position: \(frameInfo["cameraPosition"] ?? "N/A")")
                print("Camera intrinsics:")
                print(frame.camera.intrinsics)
                
                // Depth information
                if frameInfo["hasSceneDepth"] as? Bool == true {
                    print("✅ SceneDepth available!")
                    print("   Depth map size: \(frameInfo["depthMapWidth"] ?? "?")x\(frameInfo["depthMapHeight"] ?? "?")")
                } else {
                    print("❌ SceneDepth is nil")
                }
            }
            
            processFrame(frame)
            
            // Save individual frames less frequently (every 60th frame) to reduce memory usage
            // This reduces memory pressure significantly while still capturing key frames
            // Set to 0 to disable frame saving entirely (saves most memory)
            let SAVE_FRAMES_INTERVAL = 60
            if SAVE_FRAMES_INTERVAL > 0 && totalFrameCount % SAVE_FRAMES_INTERVAL == 0 {
                saveIndividualFrame(frame, frameNumber: totalFrameCount)
            }
        }
    }
    
    // MARK: - Individual Frame Access Methods
    
    /// Save an individual frame as a JPEG image file and add file path to JSON
    /// Saved with the same base name as video/JSON files for easy deletion
    /// Frames are upscaled to target resolution for high quality textures
    /// NOTE: Frame saving is memory-intensive. Set SAVE_FRAMES_INTERVAL to 0 to disable.
    private func saveIndividualFrame(_ frame: ARFrame, frameNumber: Int) {
        // Only save if we have a recording base name
        guard let baseName = recordingBaseName else {
            return
        }
        
        let capturedImage = frame.capturedImage
        
            // Process frame saving asynchronously to avoid blocking main thread
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                
                // Upscale frame to target resolution for high quality (same as video)
                guard let upscaledBuffer = self.upscalePixelBuffer(capturedImage, toWidth: self.targetWidth, toHeight: self.targetHeight) else {
                    print("Warning: Failed to upscale frame for saving")
                    return
                }
                
                // Convert upscaled CVPixelBuffer to UIImage
                if let uiImage = self.pixelBufferToUIImage(upscaledBuffer) {
                    // Save to Documents directory (same location as video/JSON)
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    // Format: {baseName}_frame_{frameNumber}_{timestamp}.jpg
                    let timestamp = Int(frame.timestamp * 1000) // Convert to milliseconds
                    let frameFileName = "\(baseName)_frame_\(frameNumber)_\(timestamp).jpg"
                    let fileURL = documentsPath.appendingPathComponent(frameFileName)
                    
                    // Use lower compression quality (0.7) to reduce memory usage
                    // Store file path in JSON instead of base64 to save memory
                    // Base64 encoding uses ~33% more memory and causes crashes on long recordings
                    if let jpegData = uiImage.jpegData(compressionQuality: 0.7) {
                        // Save the image file
                        do {
                            try jpegData.write(to: fileURL)
                            print("💾 Saved frame (\(self.targetWidth)x\(self.targetHeight)) to: \(fileURL.lastPathComponent)")
                            
                            // Store file path in JSON instead of base64 to save memory
                            let fileName = fileURL.lastPathComponent
                            self.addImagePathToDepthFrame(timestamp: frame.timestamp, fileName: fileName)
                        } catch {
                            print("⚠️ Failed to save frame image: \(error.localizedDescription)")
                        }
                    }
                }
            }
    }
    
    /// Add image file path to the corresponding depth frame (matched by timestamp)
    /// Using file path instead of base64 to save memory (base64 uses ~33% more memory)
    private func addImagePathToDepthFrame(timestamp: TimeInterval, fileName: String) {
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            self.findAndUpdateDepthFrame(timestamp: timestamp, fileName: fileName, retryCount: 0)
        }
    }
    
    /// Helper to find and update depth frame with image file path (with retry mechanism)
    private func findAndUpdateDepthFrame(timestamp: TimeInterval, fileName: String, retryCount: Int) {
        let tolerance: TimeInterval = 0.001 // 1ms tolerance
        
        if let index = self.depthFrames.firstIndex(where: { abs($0.timestamp - timestamp) < tolerance }) {
            // Create updated depth frame with image file path
            let oldFrame = self.depthFrames[index]
            let updatedFrame = DepthFrameData(
                timestamp: oldFrame.timestamp,
                intrinsics: oldFrame.intrinsics,
                cameraTransform: oldFrame.cameraTransform,
                transform: oldFrame.transform,
                position: oldFrame.position,
                orientation: oldFrame.orientation,
                eulerAngles: oldFrame.eulerAngles,
                capturedImageWidth: oldFrame.capturedImageWidth,
                capturedImageHeight: oldFrame.capturedImageHeight,
                depthToImageScale: oldFrame.depthToImageScale,
                depthMapFilePath: oldFrame.depthMapFilePath,
                depthMapWidth: oldFrame.depthMapWidth,
                depthMapHeight: oldFrame.depthMapHeight,
                imageFilePath: fileName
            )
            
            // Replace the old frame with updated one
            self.depthFrames[index] = updatedFrame
            print("✅ Added image file path to depth frame (timestamp: \(timestamp), file: \(fileName))")
        } else if retryCount < 3 {
            // Retry after a small delay in case depth frame hasn't been added yet
            recordingQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                self.findAndUpdateDepthFrame(timestamp: timestamp, fileName: fileName, retryCount: retryCount + 1)
            }
        } else {
            print("⚠️ Warning: Could not find matching depth frame for timestamp: \(timestamp) after \(retryCount) retries")
        }
    }
    
    /// Convert CVPixelBuffer to UIImage
    /// This allows you to extract individual frames as images
    func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Extract frame information as a dictionary for inspection
    /// This method returns all available frame data in a readable format
    func getFrameInfo(_ frame: ARFrame) -> [String: Any] {
        let capturedImage = frame.capturedImage
        let width = CVPixelBufferGetWidth(capturedImage)
        let height = CVPixelBufferGetHeight(capturedImage)
        let pixelFormat = CVPixelBufferGetPixelFormatType(capturedImage)
        
        // Extract camera position
        let position = simd_float3(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        
        var frameInfo: [String: Any] = [
            "timestamp": frame.timestamp,
            "imageWidth": width,
            "imageHeight": height,
            "pixelFormat": pixelFormat,
            "cameraPosition": ["x": position.x, "y": position.y, "z": position.z],
            "hasSceneDepth": frame.sceneDepth != nil,
            "hasSmoothedSceneDepth": frame.smoothedSceneDepth != nil
        ]
        
        // Add depth info if available
        if let sceneDepth = frame.sceneDepth {
            let depthMap = sceneDepth.depthMap
            frameInfo["depthMapWidth"] = CVPixelBufferGetWidth(depthMap)
            frameInfo["depthMapHeight"] = CVPixelBufferGetHeight(depthMap)
        }
        
        return frameInfo
    }
    
    private func checkLighting(frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        // Sample brightness from center region
        let sampleSize = min(100, width / 4)
        let startX = (width - sampleSize) / 2
        let startY = (height - sampleSize) / 2
        
        var totalBrightness: Float = 0
        var sampleCount = 0
        
        // Sample pixels (YUV format - Y plane is first)
        for y in startY..<min(startY + sampleSize, height) {
            let row = baseAddress.advanced(by: y * bytesPerRow)
            let pixelRow = row.assumingMemoryBound(to: UInt8.self)
            for x in startX..<min(startX + sampleSize, width) {
                let pixel = pixelRow[x]
                totalBrightness += Float(pixel)
                sampleCount += 1
            }
        }
        
        if sampleCount > 0 {
            let averageBrightness = totalBrightness / Float(sampleCount)
            // Threshold: below 80 is too dark
            DispatchQueue.main.async {
                if averageBrightness < 80 {
                    self.lightingWarning = "Lighting is not proper"
                } else {
                    self.lightingWarning = nil
                }
            }
        }
    }
    
    private func trackCameraMovement(frame: ARFrame) {
        let currentPosition = simd_float3(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        
        if let lastPos = lastCameraPosition {
            let distance = simd_distance(currentPosition, lastPos)
            if distance > 0.01 { // Significant movement
                cameraPositions.append(currentPosition)
                
                // Keep only last 60 positions (2 seconds at 30fps)
                if cameraPositions.count > 60 {
                    cameraPositions.removeFirst()
                }
                
                // Calculate rotation progress based on camera movement
                updateScanningProgress()
            }
        } else {
            cameraPositions.append(currentPosition)
        }
        
        lastCameraPosition = currentPosition
        
        // Calculate rotation angle from camera transform
        let rotationMatrix = simd_float3x3(
            simd_float3(frame.camera.transform.columns.0.x, frame.camera.transform.columns.0.y, frame.camera.transform.columns.0.z),
            simd_float3(frame.camera.transform.columns.1.x, frame.camera.transform.columns.1.y, frame.camera.transform.columns.1.z),
            simd_float3(frame.camera.transform.columns.2.x, frame.camera.transform.columns.2.y, frame.camera.transform.columns.2.z)
        )
        
        // Extract yaw angle (rotation around Y axis)
        let yaw = atan2(rotationMatrix[2][0], rotationMatrix[0][0])
        DispatchQueue.main.async {
            self.rotationAngle = Float(yaw)
        }
    }
    
    private func updateScanningProgress() {
        guard cameraPositions.count >= 10 else {
            DispatchQueue.main.async {
                self.scanningProgress = 0.0
            }
            return
        }
        
        // Calculate how much the camera has moved around
        // Simple heuristic: more positions = more coverage
        let progress = min(1.0, Float(cameraPositions.count) / 60.0)
        
        DispatchQueue.main.async {
            self.scanningProgress = progress
        }
    }
}

// AR View Representable
struct ARViewRepresentable: UIViewControllerRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIViewController(context: Context) -> ARViewController {
        let viewController = ARViewController()
        viewController.cameraManager = cameraManager
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: ARViewController, context: Context) {
        // Update if needed
    }
}

class ARViewController: UIViewController {
    var cameraManager: CameraManager?
    private var arView: ARSCNView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.backgroundColor = .black
        view.addSubview(arView)
        
        // Set session when available
        if let session = cameraManager?.arSession {
            arView.session = session
            print("ARSCNView session set")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Update session if needed
        if let session = cameraManager?.arSession {
            if arView.session != session {
                arView.session = session
                print("ARSCNView session updated")
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        arView.frame = view.bounds
    }
}
