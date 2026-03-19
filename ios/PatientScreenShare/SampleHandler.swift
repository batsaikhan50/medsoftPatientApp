import ReplayKit
import OSLog

let broadcastLogger = OSLog(subsystem: "com.batsaikhan.medsoftPatient", category: "Broadcast")

private enum AppConstants {
    static let appGroupIdentifier = "group.com.medsoftPatient"
}

class SampleHandler: RPBroadcastSampleHandler {

    private var clientConnection: SocketConnection?
    private var uploader: SampleUploader?
    private var frameCount: Int = 0

    var socketFilePath: String {
        let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        )
        return sharedContainer?.appendingPathComponent("rtc_SSFD").path ?? ""
    }

    override init() {
        super.init()
        if let connection = SocketConnection(filePath: socketFilePath) {
            clientConnection = connection
            setupConnection()
            uploader = SampleUploader(connection: connection)
        }
        os_log(.debug, log: broadcastLogger, "SampleHandler init, socket: %{public}s", socketFilePath)
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        frameCount = 0
        DarwinNotificationCenter.shared.postNotification(.broadcastStarted)
        openConnection()
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        DarwinNotificationCenter.shared.postNotification(.broadcastStopped)
        clientConnection?.close()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case RPSampleBufferType.video:
            uploader?.send(sample: sampleBuffer)
        default:
            break
        }
    }
}

private extension SampleHandler {

    func setupConnection() {
        clientConnection?.didClose = { [weak self] (error: Error?) in
            os_log(.debug, log: broadcastLogger, "client connection did close %{public}s", String(describing: error))

            if let error = error {
                self?.finishBroadcastWithError(error)
            } else {
                let customError = NSError(
                    domain: RPRecordingErrorDomain,
                    code: 10001,
                    userInfo: [NSLocalizedDescriptionKey: "Screen sharing stopped"]
                )
                self?.finishBroadcastWithError(customError)
            }
        }
    }

    func openConnection() {
        let queue = DispatchQueue(label: "broadcast.connectTimer")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard self?.clientConnection?.open() == true else {
                return
            }
            timer.cancel()
        }
        timer.resume()
    }
}
