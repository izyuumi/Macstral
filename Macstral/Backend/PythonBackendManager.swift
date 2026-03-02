import Foundation

// MARK: - PythonBackendManager

/// Downloads a standalone Python runtime, installs dependencies, downloads the Voxtral model,
/// and launches the voxtral_server.py WebSocket inference server.
@MainActor
final class PythonBackendManager: NSObject {

    // MARK: - Constants

    private static let supportDir = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!.appendingPathComponent("Macstral")

    private static let pythonDir = supportDir.appendingPathComponent("python")
    private static let envDir = supportDir.appendingPathComponent("env")
    private static let modelDir = supportDir.appendingPathComponent("models/voxtral-4bit")

    private static let pythonBinary = pythonDir
        .appendingPathComponent("python/bin/python3.11")

    private static let pythonTarURL: URL = {
        #if arch(arm64)
        let arch = "aarch64"
        #else
        let arch = "x86_64"
        #endif
        return URL(
            string: "https://github.com/indygreg/python-build-standalone/releases/download/20241016/cpython-3.11.10+20241016-\(arch)-apple-darwin-install_only.tar.gz"
        )!
    }()

    /// Expected SHA-256 checksums for the Python tarballs (release 20241016).
    private static let pythonTarSHA256: String = {
        #if arch(arm64)
        return "5a69382da99c4620690643517ca1f1f53772331b347e75f536088c42a4cf6620"
        #else
        return "1e23ffe5bc473e1323ab8f51464da62d77399afb423babf67f8e13c82b69c674"
        #endif
    }()

    private static let quantizedModelRevision = "fdebf7b2af834a1db4b8a3c99ab7480b333adf9e"
    private static let baseModelRevision = "b45b4dc60caf4ad824163aaa0a72adc0ad7beeaf"
    private static let voxtralMiniRevision = "3060fe34b35ba5d44202ce9ff3c097642914f8f3"
    private static let modelAssets: [(filename: String, url: URL)] = [
        ("config.json", quantizedModelFileURL(filename: "config.json")),
        ("model.safetensors", quantizedModelFileURL(filename: "model.safetensors")),
        ("model.safetensors.index.json", quantizedModelFileURL(filename: "model.safetensors.index.json")),
        ("tekken.json", quantizedModelFileURL(filename: "tekken.json")),
    ]

    private static func quantizedModelFileURL(filename: String) -> URL {
        URL(
            string: "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/\(quantizedModelRevision)/\(filename)"
        )!
    }

    private static func baseModelFileURL(filename: String) -> URL {
        URL(
            string: "https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602/resolve/\(baseModelRevision)/\(filename)"
        )!
    }

    private static func voxtralMiniFileURL(filename: String) -> URL {
        URL(
            string: "https://huggingface.co/mistralai/Voxtral-Mini-3B-2507/resolve/\(voxtralMiniRevision)/\(filename)"
        )!
    }

    // MARK: - Public Callbacks

    var onStatusChange: ((BackendStatus) -> Void)?
    var onSetupProgress: ((SetupStep, Double, String) -> Void)?
    var onLog: ((String) -> Void)?

    // MARK: - Public State

    private(set) var serverPort: Int?
    private var serverProcess: Process?
    private var isActive = false
    private var expectedTerminatingProcessID: ObjectIdentifier?
    private var currentSetupToken = UUID()
    private var recentServerErrorOutput = ""

    var isRunning: Bool { isActive }

    // MARK: - URLSession for progress tracking

    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var activeDownloadContinuation: CheckedContinuation<URL, Error>?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadExpectedBytes: Int64 = 0
    private var activeDownloadReceivedBytes: Int64 = 0
    private var activeDownloadStepWeight: Double = 0
    private var activeDownloadBaseProgress: Double = 0
    private var activeDownloadStep: SetupStep = .downloadingPython

    // MARK: - Prepare and Start

    /// Runs all setup steps then launches the inference server.
    func prepareAndStart() async {
        let setupToken = UUID()
        currentSetupToken = setupToken

        do {
            // Fail fast on Intel Macs: MLX only supports Apple Silicon.
            #if !arch(arm64)
            throw SetupError.unsupportedArchitecture(
                "This app requires Apple Silicon (arm64). MLX does not support Intel Macs."
            )
            #endif

            try checkSetupValidity(setupToken)
            try await setupPython()
            try checkSetupValidity(setupToken)
            try await installDeps()
            try checkSetupValidity(setupToken)
            // Model download is handled by voxmlx.load_model() during server startup.
            // Report the step as pending (not complete) so the UI correctly shows that the
            // model has not been fetched yet; launchServer()/waitForServerPort will update
            // this step as the server progresses through loading.
            reportStep(.downloadingModel, progress: 0.0, status: "Model will be fetched by voxmlx on first launch...")
            try checkSetupValidity(setupToken)
            try await launchServer()
            try checkSetupValidity(setupToken)
        } catch is CancellationError {
            guard currentSetupToken == setupToken else { return }
            resetActiveDownload()
            if !isActive {
                onStatusChange?(.stopped)
            }
        } catch {
            guard currentSetupToken == setupToken else { return }
            let message = error.localizedDescription
            log("[PythonBackendManager] Setup failed: \(message)")
            reportStep(.error(message), progress: 0, status: "Setup failed: \(message)")
            onStatusChange?(.error(message))
        }
    }

    // MARK: - Stop

    func stop() {
        currentSetupToken = UUID()
        cancelActiveDownload()
        if let process = serverProcess {
            expectedTerminatingProcessID = ObjectIdentifier(process)
            process.terminate()
        }
        serverProcess = nil
        serverPort = nil
        isActive = false
        onStatusChange?(.stopped)
    }

    // MARK: - Step 1: Download Python

    private func setupPython() async throws {
        try Task.checkCancellation()
        let fm = FileManager.default

        if fm.fileExists(atPath: Self.pythonBinary.path) {
            log("[PythonBackendManager] Python already installed.")
            reportStep(.downloadingPython, progress: 1.0, status: "Python runtime ready")
            return
        }

        reportStep(.downloadingPython, progress: 0, status: "Downloading Python runtime...")

        try fm.createDirectory(at: Self.pythonDir, withIntermediateDirectories: true)

        let tarPath = try await downloadFile(
            from: Self.pythonTarURL,
            step: .downloadingPython,
            stepWeight: 0.25,
            baseProgress: 0.0
        )

        // Verify SHA-256 checksum before extraction to guard against corrupted downloads.
        reportStep(.downloadingPython, progress: 0.22, status: "Verifying Python runtime checksum...")
        let expectedSHA256 = Self.pythonTarSHA256
        let actualSHA256: String = try await Task.detached {
            let shasum = Process()
            shasum.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
            shasum.arguments = ["-a", "256", tarPath.path]
            let pipe = Pipe()
            shasum.standardOutput = pipe
            try shasum.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            shasum.waitUntilExit()
            guard shasum.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8),
                  let hash = output.split(separator: " ").first.map(String.init)
            else { return "" }
            return hash
        }.value
        guard actualSHA256 == expectedSHA256 else {
            try? fm.removeItem(at: tarPath)
            throw SetupError.checksumMismatch(
                "Python tarball checksum mismatch.\nExpected: \(expectedSHA256)\nActual:   \(actualSHA256)"
            )
        }
        log("[PythonBackendManager] Python tarball checksum verified.")

        reportStep(.downloadingPython, progress: 0.25, status: "Extracting Python runtime...")

        // Extract tar.gz off the main actor to avoid blocking the UI thread.
        let pythonDirPath = Self.pythonDir.path
        let extractStatus: Int32 = try await Task.detached {
            let extract = Process()
            extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            extract.arguments = ["xzf", tarPath.path, "-C", pythonDirPath]
            try extract.run()
            extract.waitUntilExit()
            return extract.terminationStatus
        }.value

        guard extractStatus == 0 else {
            throw SetupError.extractionFailed("tar exited with status \(extractStatus)")
        }

        // Clean up tar file
        try? fm.removeItem(at: tarPath)

        log("[PythonBackendManager] Python extracted successfully.")
        reportStep(.downloadingPython, progress: 1.0, status: "Python runtime ready")
    }

    // MARK: - Step 2: Install Dependencies

    private func installDeps() async throws {
        try Task.checkCancellation()
        let fm = FileManager.default
        let pythonBinaryPath = Self.pythonBinary.path
        let envDirPath = Self.envDir.path

        // A stamp file records which dependency set is installed. When the pinned
        // commit changes, the stamp won't match and we'll reinstall.
        let depsStamp = Self.envDir.appendingPathComponent(".macstral_deps_stamp")
        let expectedStamp = "voxmlx-48bfdec9+websockets==15.0.1"
        let currentStamp = (try? String(contentsOf: depsStamp, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentStamp == expectedStamp {
            log("[PythonBackendManager] Dependencies already installed.")
            reportStep(.installingDeps, progress: 1.0, status: "Dependencies ready")
            return
        }

        reportStep(.installingDeps, progress: 0.1, status: "Installing Python dependencies...")

        try fm.createDirectory(at: Self.envDir, withIntermediateDirectories: true)

        let packages = [
            // Pinned to an immutable commit hash to prevent supply-chain risk from mutable branches.
            "voxmlx @ git+https://github.com/T0mSIlver/voxmlx.git@48bfdec9bc4f4f01390b25b0e098deae6dd3ae6c",
            "websockets==15.0.1",
        ]

        let (pipStatus, pipOutput): (Int32, Data) = try await Task.detached {
            let pip = Process()
            pip.executableURL = URL(fileURLWithPath: pythonBinaryPath)
            var args = [
                "-m", "pip", "install",
                "--upgrade",
                "--target", envDirPath,
            ]
            args.append(contentsOf: packages)
            pip.arguments = args
            let pipOut = Pipe()
            pip.standardOutput = pipOut
            pip.standardError = pipOut
            try pip.run()
            let outputData = pipOut.fileHandleForReading.readDataToEndOfFile()
            pip.waitUntilExit()
            return (pip.terminationStatus, outputData)
        }.value

        if pipStatus != 0 {
            let output = String(data: pipOutput, encoding: .utf8) ?? ""
            throw SetupError.pipInstallFailed("pip exited with status \(pipStatus): \(output)")
        }

        try expectedStamp.write(to: depsStamp, atomically: true, encoding: .utf8)
        log("[PythonBackendManager] Dependencies installed.")
        reportStep(.installingDeps, progress: 1.0, status: "Dependencies ready")
    }

    // MARK: - Step 3: Download Model

    private func downloadModel() async throws {
        try Task.checkCancellation()
        let fm = FileManager.default

        let allFilesExist = Self.modelAssets.allSatisfy { asset in
            let filePath = Self.modelDir.appendingPathComponent(asset.filename).path
            guard fm.fileExists(atPath: filePath),
                  let attrs = try? fm.attributesOfItem(atPath: filePath),
                  let size = attrs[.size] as? Int64
            else { return false }
            return size > 0
        }
        if allFilesExist {
            log("[PythonBackendManager] Model already downloaded.")
            reportStep(.downloadingModel, progress: 1.0, status: "Model ready")
            return
        }

        try fm.createDirectory(at: Self.modelDir, withIntermediateDirectories: true)

        let totalFiles = Self.modelAssets.count
        for (index, asset) in Self.modelAssets.enumerated() {
            try Task.checkCancellation()
            let url = asset.url
            let filename = asset.filename
            let dest = Self.modelDir.appendingPathComponent(filename)

            if fm.fileExists(atPath: dest.path) {
                log("[PythonBackendManager] \(filename) already exists, skipping.")
                let fileProgress = Double(index + 1) / Double(totalFiles)
                reportStep(.downloadingModel, progress: fileProgress, status: "Downloading model: \(filename)...")
                continue
            }

            let baseProgress = Double(index) / Double(totalFiles)
            let stepWeight = 1.0 / Double(totalFiles)

            reportStep(.downloadingModel, progress: baseProgress, status: "Downloading \(filename)...")

            let tmpPath = try await downloadFile(
                from: url,
                step: .downloadingModel,
                stepWeight: stepWeight,
                baseProgress: baseProgress
            )

            try fm.moveItem(at: tmpPath, to: dest)
            log("[PythonBackendManager] Downloaded \(filename)")
        }

        reportStep(.downloadingModel, progress: 1.0, status: "Model ready")
    }

    // MARK: - Step 4: Launch Server

    private func launchServer() async throws {
        try Task.checkCancellation()
        reportStep(.launching, progress: 0.0, status: "Starting Voxtral server...")
        onStatusChange?(.starting)

        guard let scriptURL = Bundle.main.url(forResource: "voxtral_server", withExtension: "py") else {
            throw SetupError.missingResource("voxtral_server.py not found in app bundle")
        }

        let process = Process()
        process.executableURL = Self.pythonBinary
        process.arguments = [scriptURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["MACSTRAL_ENV_DIR"] = Self.envDir.path
        environment["MACSTRAL_MODEL_DIR"] = Self.modelDir.path
        let pythonBinPath = Self.pythonBinary.deletingLastPathComponent().path
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = existingPath.isEmpty ? pythonBinPath : "\(pythonBinPath):\(existingPath)"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let processID = ObjectIdentifier(process)
        let manager = self
        process.terminationHandler = { terminatedProcess in
            Task { @MainActor in
                manager.handleServerTermination(terminatedProcess, processID: processID)
            }
        }

        try process.run()
        serverProcess = process
        recentServerErrorOutput = ""

        Task.detached {
            let handle = stderrPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty {
                    return
                }
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { continue }
                await MainActor.run {
                    manager.appendRecentServerError(text)
                    manager.log("[voxtral_server stderr] \(text)")
                }
            }
        }

        let port = try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw SetupError.serverStartFailed("Server start failed unexpectedly.") }
                return try await self.waitForServerPort(stdoutPipe: stdoutPipe)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 600_000_000_000)
                throw SetupError.serverStartFailed("Timed out waiting for Voxtral server to become ready.")
            }
            let resolvedPort = try await group.next() ?? 0
            group.cancelAll()
            return resolvedPort
        }

        serverPort = port
        isActive = true
        expectedTerminatingProcessID = nil
        log("[PythonBackendManager] Server running on port \(port)")
        reportStep(.ready, progress: 1.0, status: "Voxtral ready")
        onStatusChange?(.ready)
    }

    // MARK: - Download Helper

    /// Downloads a file with progress tracking. Returns the local file URL.
    private func downloadFile(from url: URL, step: SetupStep, stepWeight: Double, baseProgress: Double) async throws -> URL {
        activeDownloadStep = step
        activeDownloadStepWeight = stepWeight
        activeDownloadBaseProgress = baseProgress
        activeDownloadReceivedBytes = 0
        activeDownloadExpectedBytes = 0

        let manager = self
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let task = downloadSession.downloadTask(with: url)
                activeDownloadContinuation = continuation
                activeDownloadTask = task
                task.resume()
            }
        }, onCancel: {
            Task { @MainActor in
                manager.cancelActiveDownload()
            }
        }
        )
    }

    // MARK: - Reporting

    private func reportStep(_ step: SetupStep, progress: Double, status: String) {
        onSetupProgress?(step, progress, status)
    }

    private func log(_ message: String) {
        onLog?(message)
    }

    private func checkSetupValidity(_ token: UUID) throws {
        if token != currentSetupToken {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private func cancelActiveDownload() {
        activeDownloadTask?.cancel()
        if let continuation = activeDownloadContinuation {
            activeDownloadContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        activeDownloadTask = nil
    }

    private func resetActiveDownload() {
        activeDownloadContinuation = nil
        activeDownloadTask = nil
    }

    private func completeActiveDownload(with result: Result<URL, Error>) {
        guard let continuation = activeDownloadContinuation else { return }
        activeDownloadContinuation = nil
        activeDownloadTask = nil
        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func appendRecentServerError(_ text: String) {
        recentServerErrorOutput += text
        if recentServerErrorOutput.count > 8_000 {
            recentServerErrorOutput = String(recentServerErrorOutput.suffix(8_000))
        }
    }

    private func waitForServerPort(stdoutPipe: Pipe) async throws -> Int {
        let manager = self
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            Task.detached {
                let handle = stdoutPipe.fileHandleForReading
                var accumulated = Data()
                var loadingModelSeen = false

                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        await MainActor.run {
                            let stderrText = manager.recentServerErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                            if stderrText.isEmpty {
                                continuation.resume(throwing: SetupError.serverStartFailed("Server process exited before printing port."))
                            } else {
                                continuation.resume(throwing: SetupError.serverStartFailed("Server process exited before printing port. stderr: \(stderrText)"))
                            }
                        }
                        return
                    }
                    accumulated.append(chunk)

                    guard let text = String(data: accumulated, encoding: .utf8) else { continue }
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed == "loading_model" && !loadingModelSeen {
                            loadingModelSeen = true
                            await MainActor.run {
                                // Model is now actively being downloaded/loaded by voxmlx.
                                manager.reportStep(.downloadingModel, progress: 0.5, status: "Loading Voxtral model into memory...")
                                manager.reportStep(.launching, progress: 0.3, status: "Loading Voxtral model into memory...")
                            }
                        } else if let portNum = Int(trimmed), portNum > 0 {
                            await MainActor.run {
                                // Model fully loaded — mark the download step complete before transitioning to ready.
                                manager.reportStep(.downloadingModel, progress: 1.0, status: "Model ready")
                            }
                            continuation.resume(returning: portNum)
                            return
                        }
                    }
                }
            }
        }
    }

    private func handleServerTermination(_ process: Process, processID: ObjectIdentifier) {
        if expectedTerminatingProcessID == processID {
            expectedTerminatingProcessID = nil
            return
        }
        guard serverProcess === process else { return }
        serverProcess = nil
        serverPort = nil
        isActive = false
        let stderrText = recentServerErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if stderrText.isEmpty {
            message = "Voxtral server exited unexpectedly."
        } else {
            message = "Voxtral server exited unexpectedly: \(stderrText)"
        }
        onStatusChange?(.error(message))
    }
}

// MARK: - URLSessionDownloadDelegate

extension PythonBackendManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The system deletes `location` as soon as this method returns, so we must move the
        // file to a path we control before doing any async work.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
        } catch {
            Task { @MainActor in
                self.completeActiveDownload(with: .failure(error))
            }
            return
        }

        Task { @MainActor in
            // Guard against stale callbacks: if this task was cancelled or superseded by a
            // newer download, discard the temp file and do not resume the continuation.
            guard self.activeDownloadTask === downloadTask else {
                try? FileManager.default.removeItem(at: tmp)
                return
            }

            // Check HTTP response status before accepting the downloaded file.
            if let httpResponse = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                try? FileManager.default.removeItem(at: tmp)
                let error = SetupError.downloadFailed("HTTP \(httpResponse.statusCode) from \(downloadTask.originalRequest?.url?.absoluteString ?? "unknown URL")")
                self.completeActiveDownload(with: .failure(error))
                return
            }

            self.completeActiveDownload(with: .success(tmp))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard self.activeDownloadTask === downloadTask else { return }
            activeDownloadReceivedBytes = totalBytesWritten
            activeDownloadExpectedBytes = totalBytesExpectedToWrite

            if totalBytesExpectedToWrite > 0 {
                let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let overallProgress = activeDownloadBaseProgress + fraction * activeDownloadStepWeight

                let mb = Double(totalBytesWritten) / 1_048_576.0
                let totalMB = Double(totalBytesExpectedToWrite) / 1_048_576.0
                let statusText = String(format: "Downloading... %.0f / %.0f MB", mb, totalMB)
                reportStep(activeDownloadStep, progress: overallProgress, status: statusText)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.completeActiveDownload(with: .failure(error))
            }
        }
    }
}

// MARK: - SetupError

enum SetupError: LocalizedError {
    case extractionFailed(String)
    case pipInstallFailed(String)
    case missingResource(String)
    case serverStartFailed(String)
    case downloadFailed(String)
    case checksumMismatch(String)
    case unsupportedArchitecture(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .pipInstallFailed(let msg): return "Dependency install failed: \(msg)"
        case .missingResource(let msg): return msg
        case .serverStartFailed(let msg): return "Server start failed: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .checksumMismatch(let msg): return "Checksum verification failed: \(msg)"
        case .unsupportedArchitecture(let msg): return "Unsupported architecture: \(msg)"
        }
    }
}
