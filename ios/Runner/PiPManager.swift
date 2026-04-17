import AVKit
import Accelerate
import Flutter
import WebRTC
import flutter_webrtc

// MARK: - Custom Video View using AVSampleBufferDisplayLayer

class CustomVideoView: UIView {
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    var sampleBufferLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        sampleBufferLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Frame Renderer: RTCVideoFrame -> CMSampleBuffer

class RTCFrameRenderer: NSObject, RTCVideoRenderer {
    private let displayLayer: AVSampleBufferDisplayLayer
    private var pixelBufferPool: CVPixelBufferPool?
    var frameCount = 0

    /// Render every Nth frame
    var frameSkip: Int = 2

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init()
    }

    func setSize(_ size: CGSize) {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pixelBufferPool)
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame else { return }

        frameCount += 1
        if frameCount % frameSkip != 0 { return }

        guard let pixelBuffer = extractPixelBuffer(from: frame) else { return }
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer, timestamp: frame.timeStampNs) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            self.displayLayer.enqueue(sampleBuffer)
        }
    }

    private func extractPixelBuffer(from frame: RTCVideoFrame) -> CVPixelBuffer? {
        // Zero-copy path (fast) — preferred
        if let rtcPixelBuffer = frame.buffer as? RTCCVPixelBuffer {
            return rtcPixelBuffer.pixelBuffer
        }
        // I420 → BGRA using Accelerate framework (hardware-accelerated, fast)
        if let i420Buffer = frame.buffer as? RTCI420Buffer {
            return convertI420ToPixelBufferFast(i420Buffer, width: Int(frame.width), height: Int(frame.height))
        }
        return nil
    }

    /// Fast I420 → BGRA conversion using Apple's Accelerate framework
    private func convertI420ToPixelBufferFast(_ buffer: RTCI420Buffer, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        }

        guard let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        let dstBase = CVPixelBufferGetBaseAddress(pb)!
        let dstStride = CVPixelBufferGetBytesPerRow(pb)

        // Set up vImage buffers for Y, Cb, Cr planes
        var yPlane = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: buffer.dataY),
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: Int(buffer.strideY)
        )
        var uPlane = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: buffer.dataU),
            height: vImagePixelCount(height / 2),
            width: vImagePixelCount(width / 2),
            rowBytes: Int(buffer.strideU)
        )
        var vPlane = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: buffer.dataV),
            height: vImagePixelCount(height / 2),
            width: vImagePixelCount(width / 2),
            rowBytes: Int(buffer.strideV)
        )
        var destBuffer = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: dstStride
        )

        // YUV to ARGB conversion info (BT.601 video range)
        var info = vImage_YpCbCrToARGB()
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 16, CbCr_bias: 128,
            YpRangeMax: 235, CbCrRangeMax: 240,
            YpMax: 235, YpMin: 16,
            CbCrMax: 240, CbCrMin: 16
        )

        let error = vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_601_4!,
            &pixelRange,
            &info,
            kvImage420Yp8_Cb8_Cr8,
            kvImageARGB8888,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else { return nil }

        // Convert I420 to ARGB
        let convError = vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
            &yPlane, &uPlane, &vPlane,
            &destBuffer,
            &info,
            nil,  // no permuteMap — default ARGB order
            255,  // alpha fill
            vImage_Flags(kvImageNoFlags)
        )

        guard convError == kvImageNoError else { return nil }

        // ARGB → BGRA permutation (swap R and B channels)
        var permuteMap: [UInt8] = [3, 2, 1, 0]  // ARGB → BGRA
        vImagePermuteChannels_ARGB8888(&destBuffer, &destBuffer, &permuteMap, vImage_Flags(kvImageNoFlags))

        return pb
    }

    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timestamp: Int64) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let format = formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: timestamp, timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

// MARK: - PiP Manager

@available(iOS 15.0, *)
class PiPManager: NSObject, AVPictureInPictureControllerDelegate {
    static var shared: PiPManager?

    private var pipController: AVPictureInPictureController?
    private var videoView: CustomVideoView?
    private var frameRenderer: RTCFrameRenderer?
    private var remoteVideoTrack: RTCVideoTrack?
    private var pipContentSource: AVPictureInPictureController.ContentSource?
    private var isRendererAttached = false
    private var hasRemoteTrack = false
    private var isPiPActive = false
    private var isPiPSuppressed = false

    override init() {
        super.init()
    }

    func setup() {
        print("PiPManager: setup()")

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("PiPManager: Audio session error: \(error)")
        }

        videoView = CustomVideoView(frame: CGRect(x: 0, y: 0, width: 180, height: 320))
        frameRenderer = RTCFrameRenderer(displayLayer: videoView!.sampleBufferLayer)

        // Add to the window BELOW the Flutter view controller's view.
        if let window = UIApplication.shared.keyWindow {
            videoView!.frame = window.bounds
            window.insertSubview(videoView!, at: 0)
            print("PiPManager: videoView added to window behind Flutter view")
        }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: videoView!.sampleBufferLayer,
            playbackDelegate: self
        )
        pipContentSource = source
        pipController = AVPictureInPictureController(contentSource: source)
        pipController?.delegate = self
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        if #available(iOS 16.0, *) {
            pipController?.requiresLinearPlayback = true
        }
        print("PiPManager: PiP controller created")
    }

    func setRemoteTrack(trackId: String) {
        print("PiPManager: setRemoteTrack: \(trackId)")

        guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else {
            print("PiPManager: No FlutterWebRTCPlugin singleton")
            return
        }

        guard let mediaTrack = plugin.remoteTrack(forId: trackId),
              let videoTrack = mediaTrack as? RTCVideoTrack else {
            print("PiPManager: Could not find remote video track: \(trackId)")
            return
        }

        // Remove old track renderer
        if let oldTrack = remoteVideoTrack, let renderer = frameRenderer, isRendererAttached {
            oldTrack.remove(renderer)
            isRendererAttached = false
        }

        remoteVideoTrack = videoTrack
        hasRemoteTrack = true

        // Keep renderer always attached but at very low rate (~1fps).
        // CVPixelBuffer path is zero-copy so this costs almost nothing.
        // I420 path now uses Accelerate framework so it's also fast.
        // This ensures the display layer always has fresh content for auto-PiP.
        if let renderer = frameRenderer, !isRendererAttached {
            renderer.frameSkip = 30  // ~1fps in foreground
            videoTrack.add(renderer)
            isRendererAttached = true
            print("PiPManager: Renderer attached (idle ~1fps)")
        }

        print("PiPManager: Remote track set successfully")
    }

    /// Suppress auto-PiP during screen share.
    /// We keep the PiP controller and renderer alive so the display layer
    /// never goes black — we just disable auto-start so PiP doesn't fight
    /// with the ReplayKit broadcast picker UI.
    func teardownForScreenShare() {
        isPiPSuppressed = true
        stopPiP()
        pipController?.canStartPictureInPictureAutomaticallyFromInline = false
        print("PiPManager: PiP suppressed for screen share")
    }

    /// Re-enable auto-PiP after screen share ends (or once screen share
    /// is confirmed active so the user can PiP while sharing).
    func restoreAfterScreenShare() {
        guard isPiPSuppressed else {
            print("PiPManager: Restore skipped (not suppressed)")
            return
        }
        isPiPSuppressed = false
        pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        // Ensure renderer is attached and delivering frames
        if let track = remoteVideoTrack, let renderer = frameRenderer, !isRendererAttached {
            renderer.frameSkip = 30
            track.add(renderer)
            isRendererAttached = true
        }
        print("PiPManager: PiP restored after screen share")
    }

    /// Called from AppDelegate willResignActive
    func onAppWillResignActive() {
        guard hasRemoteTrack, !isPiPSuppressed else { return }
        // Restore alpha (may have been zeroed on previous foreground return)
        videoView?.alpha = 1.0
        // Switch to high frame rate for smooth PiP
        frameRenderer?.frameSkip = 2  // ~15fps
        print("PiPManager: Renderer → active (~15fps)")
    }

    /// Called from AppDelegate willEnterForeground / didBecomeActive
    func onAppDidBecomeActive() {
        guard isPiPActive || pipController?.isPictureInPictureActive == true else {
            // Not in PiP — just ensure idle state
            frameRenderer?.frameSkip = 30
            return
        }

        // 1. Make the source view transparent so any restore animation is invisible
        videoView?.alpha = 0

        // 2. Flush the display layer — removes all content so PiP window goes blank
        videoView?.sampleBufferLayer.flush()

        // 3. Stop PiP
        stopPiP()

        // 4. Switch back to idle
        frameRenderer?.frameSkip = 30
        isPiPActive = false
        print("PiPManager: PiP dismissed, renderer → idle")
    }

    func startPiP() {
        guard let controller = pipController else { return }
        if controller.isPictureInPictureActive { return }
        print("PiPManager: Starting PiP...")
        controller.startPictureInPicture()
    }

    func stopPiP() {
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
    }

    func disposePiP() {
        print("PiPManager: dispose")
        stopPiP()
        if let track = remoteVideoTrack, let renderer = frameRenderer, isRendererAttached {
            track.remove(renderer)
            isRendererAttached = false
        }
        remoteVideoTrack = nil
        hasRemoteTrack = false
        pipController = nil
        pipContentSource = nil
        videoView?.removeFromSuperview()
        videoView = nil
        frameRenderer = nil
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        isPiPActive = true
        // Ensure high frame rate
        frameRenderer?.frameSkip = 2
        print("PiPManager: PiP will start")
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        print("PiPManager: PiP started")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        isPiPActive = false
        frameRenderer?.frameSkip = 30
        print("PiPManager: PiP stopped")
    }

    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        isPiPActive = false
        frameRenderer?.frameSkip = 30
        print("PiPManager: Failed to start PiP: \(error)")
    }

    func pictureInPictureController(_ c: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // completionHandler(false) tells iOS NOT to animate PiP expanding
        // back to the inline source view. PiP just disappears cleanly.
        videoView?.alpha = 0
        videoView?.sampleBufferLayer.flush()
        frameRenderer?.frameSkip = 30
        isPiPActive = false
        completionHandler(false)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 15.0, *)
extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool {
        return false
    }

    func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
