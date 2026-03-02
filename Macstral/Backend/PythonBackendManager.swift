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

    private static let pythonTarURL = URL(
        string: "https://github.com/indygreg/python-build-standalone/releases/download/20241016/cpython-3.11.10+20241016-aarch64-apple-darwin-install_only.tar.gz"
    )!

    private static let modelFiles: [(String, String)] = [
        ("config.json", "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/main/config.json"),
        ("model.safetensors", "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/main/model.safetensors"),
        ("model.safetensors.index.json", "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/main/model.safetensors.index.json"),
        ("tekken.json", "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/main/tekken.json"),
    ]

    // MARK: - Public Callbacks

    var onStatusChange: ((BackendStatus) -> Void)?
    var onSetupProgress: ((SetupStep, Double, String) -> Void)?
    var onLog: ((String) -> Void)?

    // MARK: - Public State

    private(set) var serverPort: Int?
    private var serverProcess: Process?
    private var isActive = false

    var isRunning: Bool { isActive }

    // MARK: - URLSession for progress tracking

    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var activeDownloadContinuation: CheckedContinuation<URL, Error>?
    private var activeDownloadExpectedBytes: Int64 = 0
    private var activeDownloadReceivedBytes: Int64 = 0
    private var activeDownloadStepWeight: Double = 0
    private var activeDownloadBaseProgress: Double = 0

    // MARK: - Prepare and Start

    /// Runs all setup steps then launches the inference server.
    func prepareAndStart() async {
        do {
            try await setupPython()
            try await installDeps()
            try await downloadModel()
            try await launchServer()
        } catch {
            let message = error.localizedDescription
            log("[PythonBackendManager] Setup failed: \(message)")
            reportStep(.error(message), progress: 0, status: "Setup failed: \(message)")
            onStatusChange?(.error(message))
        }
    }

    // MARK: - Stop

    func stop() {
        serverProcess?.terminate()
        serverProcess = nil
        serverPort = nil
        isActive = false
        onStatusChange?(.stopped)
    }

    // MARK: - Step 1: Download Python

    private func setupPython() async throws {
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
            stepWeight: 0.25,
            baseProgress: 0.0
        )

        reportStep(.downloadingPython, progress: 0.25, status: "Extracting Python runtime...")

        // Extract tar.gz using /usr/bin/tar
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extract.arguments = ["xzf", tarPath.path, "-C", Self.pythonDir.path]
        try extract.run()
        extract.waitUntilExit()

        guard extract.terminationStatus == 0 else {
            throw SetupError.extractionFailed("tar exited with status \(extract.terminationStatus)")
        }

        // Clean up tar file
        try? fm.removeItem(at: tarPath)

        log("[PythonBackendManager] Python extracted successfully.")
        reportStep(.downloadingPython, progress: 1.0, status: "Python runtime ready")
    }

    // MARK: - Step 2: Install Dependencies

    private func installDeps() async throws {
        let fm = FileManager.default

        // Check if deps are already installed by looking for mlx_audio marker
        let mlxAudioMarker = Self.envDir.appendingPathComponent("mlx_audio")
        if fm.fileExists(atPath: mlxAudioMarker.path) {
            log("[PythonBackendManager] Dependencies already installed.")
            reportStep(.installingDeps, progress: 1.0, status: "Dependencies ready")
            return
        }

        reportStep(.installingDeps, progress: 0.1, status: "Installing Python dependencies...")

        try fm.createDirectory(at: Self.envDir, withIntermediateDirectories: true)

        let pip = Process()
        pip.executableURL = Self.pythonBinary
        pip.arguments = [
            "-m", "pip", "install",
            "--target", Self.envDir.path,
            "mlx-audio[stt]", "websockets",
        ]
        let pipOut = Pipe()
        pip.standardOutput = pipOut
        pip.standardError = pipOut
        try pip.run()

        // Read output in background
        let outputData = pipOut.fileHandleForReading.readDataToEndOfFile()
        pip.waitUntilExit()

        if pip.terminationStatus != 0 {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            throw SetupError.pipInstallFailed("pip exited with status \(pip.terminationStatus): \(output)")
        }

        log("[PythonBackendManager] Dependencies installed.")
        reportStep(.installingDeps, progress: 1.0, status: "Dependencies ready")
    }

    // MARK: - Step 3: Download Model

    private func downloadModel() async throws {
        let fm = FileManager.default

        // Check if model is already downloaded by looking for model.safetensors
        let modelFile = Self.modelDir.appendingPathComponent("model.safetensors")
        if fm.fileExists(atPath: modelFile.path) {
            log("[PythonBackendManager] Model already downloaded.")
            reportStep(.downloadingModel, progress: 1.0, status: "Model ready")
            return
        }

        try fm.createDirectory(at: Self.modelDir, withIntermediateDirectories: true)

        let totalFiles = Self.modelFiles.count
        for (index, (filename, urlString)) in Self.modelFiles.enumerated() {
            let url = URL(string: urlString)!
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
        reportStep(.launching, progress: 0.0, status: "Starting Voxtral server...")
        onStatusChange?(.starting)

        guard let scriptURL = Bundle.main.url(forResource: "voxtral_server", withExtension: "py") else {
            throw SetupError.missingResource("voxtral_server.py not found in app bundle")
        }

        let process = Process()
        process.executableURL = Self.pythonBinary
        process.arguments = [scriptURL.path]
        process.environment = [
            "MACSTRAL_ENV_DIR": Self.envDir.path,
            "MACSTRAL_MODEL_DIR": Self.modelDir.path,
            "PATH": Self.pythonBinary.deletingLastPathComponent().path,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        serverProcess = process

        // Read stderr in background for logging
        Task.detached { [weak self] in
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                await MainActor.run {
                    self?.log("[voxtral_server stderr] \(text)")
                }
            }
        }

        // Read port number from stdout
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            Task.detached {
                let handle = stdoutPipe.fileHandleForReading
                var accumulated = Data()
                var loadingModelSeen = false

                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        continuation.resume(throwing: SetupError.serverStartFailed("Server process exited before printing port"))
                        return
                    }
                    accumulated.append(chunk)

                    guard let text = String(data: accumulated, encoding: .utf8) else { continue }
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed == "loading_model" && !loadingModelSeen {
                            loadingModelSeen = true
                            await MainActor.run { [weak self] in
                                self?.reportStep(.launching, progress: 0.3, status: "Loading Voxtral model into memory...")
                            }
                        } else if let portNum = Int(trimmed), portNum > 0 {
                            continuation.resume(returning: portNum)
                            return
                        }
                    }
                }
            }
        }

        serverPort = port
        isActive = true
        log("[PythonBackendManager] Server running on port \(port)")
        reportStep(.ready, progress: 1.0, status: "Voxtral ready")
        onStatusChange?(.ready)
    }

    // MARK: - Download Helper

    /// Downloads a file with progress tracking. Returns the local file URL.
    private func downloadFile(from url: URL, stepWeight: Double, baseProgress: Double) async throws -> URL {
        activeDownloadStepWeight = stepWeight
        activeDownloadBaseProgress = baseProgress
        activeDownloadReceivedBytes = 0
        activeDownloadExpectedBytes = 0

        return try await withCheckedThrowingContinuation { continuation in
            activeDownloadContinuation = continuation
            let task = downloadSession.downloadTask(with: url)
            task.resume()
        }
    }

    // MARK: - Reporting

    private func reportStep(_ step: SetupStep, progress: Double, status: String) {
        onSetupProgress?(step, progress, status)
    }

    private func log(_ message: String) {
        onLog?(message)
    }
}

// MARK: - URLSessionDownloadDelegate

extension PythonBackendManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Move to a temp file we control (the system deletes `location` after this returns)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            Task { @MainActor in
                activeDownloadContinuation?.resume(returning: tmp)
                activeDownloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                activeDownloadContinuation?.resume(throwing: error)
                activeDownloadContinuation = nil
            }
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
            activeDownloadReceivedBytes = totalBytesWritten
            activeDownloadExpectedBytes = totalBytesExpectedToWrite

            if totalBytesExpectedToWrite > 0 {
                let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let overallProgress = activeDownloadBaseProgress + fraction * activeDownloadStepWeight

                // Determine current step from context
                let currentStep: SetupStep
                if activeDownloadBaseProgress < 0.01 && activeDownloadStepWeight > 0.2 {
                    currentStep = .downloadingPython
                } else {
                    currentStep = .downloadingModel
                }

                let mb = Double(totalBytesWritten) / 1_048_576.0
                let totalMB = Double(totalBytesExpectedToWrite) / 1_048_576.0
                let statusText = String(format: "Downloading... %.0f / %.0f MB", mb, totalMB)
                reportStep(currentStep, progress: overallProgress, status: statusText)
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
                activeDownloadContinuation?.resume(throwing: error)
                activeDownloadContinuation = nil
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

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .pipInstallFailed(let msg): return "Dependency install failed: \(msg)"
        case .missingResource(let msg): return msg
        case .serverStartFailed(let msg): return "Server start failed: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        }
    }
}
