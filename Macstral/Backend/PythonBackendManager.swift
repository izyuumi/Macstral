import Foundation
import CryptoKit

// MARK: - PythonBackendManager

/// Downloads a standalone Python runtime, installs dependencies, downloads the Voxtral model,
/// and launches the voxtral_server.py WebSocket inference server.
@MainActor
final class PythonBackendManager: NSObject {

    // MARK: - Constants

    private struct PythonRuntimeSpec {
        let archiveURL: URL
        let sha256: String
    }

    private struct ModelFileSpec {
        let filename: String
        let url: URL
        let sha256: String
        let sizeBytes: Int64
    }

    private static let supportDir: URL = {
        if let appSupportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return appSupportDir.appendingPathComponent("Macstral")
        }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macstral")
    }()

    private static let pythonDir = supportDir.appendingPathComponent("python")
    private static let envDir = supportDir.appendingPathComponent("env")
    private static let modelDir = supportDir.appendingPathComponent("models/voxtral-4bit")
    private static let modelVerificationMarker = modelDir.appendingPathComponent(".verified.signature")

    private static let pythonBinary = pythonDir
        .appendingPathComponent("python/bin/python3.11")

#if arch(arm64)
    private static let pythonRuntime = PythonRuntimeSpec(
        archiveURL: URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20241016/cpython-3.11.10+20241016-aarch64-apple-darwin-install_only.tar.gz")!,
        sha256: "5a69382da99c4620690643517ca1f1f53772331b347e75f536088c42a4cf6620"
    )
#elseif arch(x86_64)
    private static let pythonRuntime = PythonRuntimeSpec(
        archiveURL: URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20241016/cpython-3.11.10+20241016-x86_64-apple-darwin-install_only.tar.gz")!,
        sha256: "1e23ffe5bc473e1323ab8f51464da62d77399afb423babf67f8e13c82b69c674"
    )
#else
    private static let pythonRuntime = PythonRuntimeSpec(
        archiveURL: URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20241016/cpython-3.11.10+20241016-aarch64-apple-darwin-install_only.tar.gz")!,
        sha256: "5a69382da99c4620690643517ca1f1f53772331b347e75f536088c42a4cf6620"
    )
#endif

    private static let modelRevision = "fdebf7b2af834a1db4b8a3c99ab7480b333adf9e"

    private static let modelFiles: [ModelFileSpec] = [
        .init(
            filename: "config.json",
            url: URL(string: "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/\(modelRevision)/config.json")!,
            sha256: "02060864a4f33df5e4944684fc17f3026af4011830cac4def6e9e025315b10c5",
            sizeBytes: 1513
        ),
        .init(
            filename: "model.safetensors",
            url: URL(string: "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/\(modelRevision)/model.safetensors")!,
            sha256: "6f59b425d8a1ceb2de795454558be63937cf75b59f9c9bc77accd85aaf32af05",
            sizeBytes: 3_133_798_126
        ),
        .init(
            filename: "model.safetensors.index.json",
            url: URL(string: "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/\(modelRevision)/model.safetensors.index.json")!,
            sha256: "80f68b80cf4b1638d864d1504061a266f59e37a8d90d7b20f2e1f30c2d034c2e",
            sizeBytes: 118_632
        ),
        .init(
            filename: "tekken.json",
            url: URL(string: "https://huggingface.co/mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit/resolve/\(modelRevision)/tekken.json")!,
            sha256: "8434af1d39eba99f0ef46cf1450bf1a63fa941a26933a1ef5dbbf4adf0d00e44",
            sizeBytes: 14_910_348
        ),
    ]

    private static let modelVerificationSignature: String = {
        let parts = modelFiles.map { "\($0.filename):\($0.sha256):\($0.sizeBytes)" }
        return ([modelRevision] + parts).joined(separator: "|")
    }()

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
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadID: UUID?
    private var activeDownloadExpectedBytes: Int64 = 0
    private var activeDownloadReceivedBytes: Int64 = 0
    private var activeDownloadStepWeight: Double = 0
    private var activeDownloadBaseProgress: Double = 0

    // MARK: - Prepare and Start

    /// Runs all setup steps then launches the inference server.
    func prepareAndStart() async {
        if isActive {
            onStatusChange?(.ready)
            reportStep(.ready, progress: 1.0, status: "Voxtral ready")
            return
        }

        do {
            try Task.checkCancellation()
            try await setupPython()
            try Task.checkCancellation()
            try await installDeps()
            try Task.checkCancellation()
            try await downloadModel()
            try Task.checkCancellation()
            try await launchServer()
        } catch is CancellationError {
            return
        } catch {
            let message = error.localizedDescription
            log("[PythonBackendManager] Setup failed: \(message)")
            reportStep(.error(message), progress: 0, status: "Setup failed: \(message)")
            onStatusChange?(.error(message))
        }
    }

    // MARK: - Stop

    func stop() {
        let process = serverProcess
        serverProcess = nil
        serverPort = nil
        isActive = false
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadID = nil
        activeDownloadContinuation?.resume(throwing: CancellationError())
        activeDownloadContinuation = nil
        process?.terminate()
        onStatusChange?(.stopped)
    }

    // MARK: - Step 1: Download Python

    private func setupPython() async throws {
        let fm = FileManager.default

        if isPythonRuntimeReady() {
            log("[PythonBackendManager] Python already installed.")
            reportStep(.downloadingPython, progress: 1.0, status: "Python runtime ready")
            return
        }

        if fm.fileExists(atPath: Self.pythonDir.path) {
            try? fm.removeItem(at: Self.pythonDir)
        }

        reportStep(.downloadingPython, progress: 0, status: "Downloading Python runtime...")

        try fm.createDirectory(at: Self.pythonDir, withIntermediateDirectories: true)

        let tarPath = try await downloadFile(
            from: Self.pythonRuntime.archiveURL,
            stepWeight: 0.25,
            baseProgress: 0.0
        )
        defer { try? fm.removeItem(at: tarPath) }

        try verifySHA256(of: tarPath, expected: Self.pythonRuntime.sha256, label: "python runtime archive")

        reportStep(.downloadingPython, progress: 0.25, status: "Extracting Python runtime...")

        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        extract.arguments = ["xzf", tarPath.path, "-C", Self.pythonDir.path]
        try extract.run()
        extract.waitUntilExit()

        guard extract.terminationStatus == 0 else {
            throw SetupError.extractionFailed("tar exited with status \(extract.terminationStatus)")
        }

        guard isPythonRuntimeReady() else {
            throw SetupError.pythonValidationFailed("Downloaded runtime is not executable")
        }

        log("[PythonBackendManager] Python extracted successfully.")
        reportStep(.downloadingPython, progress: 1.0, status: "Python runtime ready")
    }

    // MARK: - Step 2: Install Dependencies

    private func installDeps() async throws {
        let fm = FileManager.default

        if areDependenciesReady() {
            log("[PythonBackendManager] Dependencies already installed.")
            reportStep(.installingDeps, progress: 1.0, status: "Dependencies ready")
            return
        }

        reportStep(.installingDeps, progress: 0.1, status: "Installing Python dependencies...")

        try fm.createDirectory(at: Self.envDir, withIntermediateDirectories: true)

        let (status, output) = try runProcess(
            executableURL: Self.pythonBinary,
            arguments: [
                "-m", "pip", "install",
                "--target", Self.envDir.path,
                "mlx-audio[stt]", "websockets",
            ],
            environment: processEnvironment(includePythonInPath: true)
        )

        if status != 0 {
            throw SetupError.pipInstallFailed("pip exited with status \(status): \(output)")
        }

        guard areDependenciesReady() else {
            throw SetupError.pipInstallFailed("Installed dependencies failed verification import")
        }

        log("[PythonBackendManager] Dependencies installed.")
        reportStep(.installingDeps, progress: 1.0, status: "Dependencies ready")
    }

    // MARK: - Step 3: Download Model

    private func downloadModel() async throws {
        let fm = FileManager.default

        if isModelReady() {
            log("[PythonBackendManager] Model already downloaded.")
            reportStep(.downloadingModel, progress: 1.0, status: "Model ready")
            return
        }

        try fm.createDirectory(at: Self.modelDir, withIntermediateDirectories: true)

        let totalFiles = Self.modelFiles.count
        let markerMatchesCurrentSpec = modelVerificationMarkerMatchesCurrentSpec()
        if !markerMatchesCurrentSpec {
            reportStep(.downloadingModel, progress: 0, status: "Verifying model files...")
        }

        for (index, file) in Self.modelFiles.enumerated() {
            let dest = Self.modelDir.appendingPathComponent(file.filename)

            if markerMatchesCurrentSpec && hasExpectedFileSize(at: dest, expectedSize: file.sizeBytes) {
                let fileProgress = Double(index + 1) / Double(totalFiles)
                reportStep(.downloadingModel, progress: fileProgress, status: "Downloading model: \(file.filename)...")
                continue
            }

            if hasExpectedFileSize(at: dest, expectedSize: file.sizeBytes) {
                do {
                    try verifySHA256(of: dest, expected: file.sha256, label: file.filename)
                    let fileProgress = Double(index + 1) / Double(totalFiles)
                    reportStep(.downloadingModel, progress: fileProgress, status: "Downloading model: \(file.filename)...")
                    continue
                } catch {
                    try? fm.removeItem(at: dest)
                }
            }

            let baseProgress = Double(index) / Double(totalFiles)
            let stepWeight = 1.0 / Double(totalFiles)

            reportStep(.downloadingModel, progress: baseProgress, status: "Downloading \(file.filename)...")

            let tmpPath = try await downloadFile(
                from: file.url,
                stepWeight: stepWeight,
                baseProgress: baseProgress
            )

            do {
                try verifySHA256(of: tmpPath, expected: file.sha256, label: file.filename)
                try fm.moveItem(at: tmpPath, to: dest)
                log("[PythonBackendManager] Downloaded \(file.filename)")
            } catch {
                try? fm.removeItem(at: tmpPath)
                throw error
            }
        }

        try writeModelVerificationMarker()
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
        process.environment = processEnvironment(includePythonInPath: true)
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor in
                guard let self, self.serverProcess === terminatedProcess else { return }
                self.serverProcess = nil
                self.serverPort = nil
                let wasActive = self.isActive
                self.isActive = false
                if wasActive {
                    let message = "Voxtral server exited with status \(terminatedProcess.terminationStatus)"
                    self.log("[PythonBackendManager] \(message)")
                    self.reportStep(.error(message), progress: 0, status: message)
                    self.onStatusChange?(.error(message))
                }
            }
        }

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
        let downloadID = UUID()
        activeDownloadStepWeight = stepWeight
        activeDownloadBaseProgress = baseProgress
        activeDownloadReceivedBytes = 0
        activeDownloadExpectedBytes = 0

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeDownloadContinuation = continuation
                let task = downloadSession.downloadTask(with: url)
                activeDownloadTask = task
                activeDownloadID = downloadID
                task.resume()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.activeDownloadID == downloadID else { return }
                self.activeDownloadTask?.cancel()
                self.activeDownloadTask = nil
                self.activeDownloadID = nil
                self.activeDownloadContinuation?.resume(throwing: CancellationError())
                self.activeDownloadContinuation = nil
            }
        }
    }

    private func isPythonRuntimeReady() -> Bool {
        guard FileManager.default.fileExists(atPath: Self.pythonBinary.path) else {
            return false
        }
        do {
            let (status, _) = try runProcess(
                executableURL: Self.pythonBinary,
                arguments: ["--version"],
                environment: processEnvironment(includePythonInPath: true)
            )
            return status == 0
        } catch {
            return false
        }
    }

    private func areDependenciesReady() -> Bool {
        guard FileManager.default.fileExists(atPath: Self.envDir.path) else {
            return false
        }
        do {
            let (status, _) = try runProcess(
                executableURL: Self.pythonBinary,
                arguments: [
                    "-c",
                    "import os, sys; sys.path.insert(0, os.environ['MACSTRAL_ENV_DIR']); import mlx_audio, websockets",
                ],
                environment: processEnvironment(includePythonInPath: true)
            )
            return status == 0
        } catch {
            return false
        }
    }

    private func isModelReady() -> Bool {
        guard modelVerificationMarkerMatchesCurrentSpec() else {
            return false
        }
        for file in Self.modelFiles {
            let path = Self.modelDir.appendingPathComponent(file.filename)
            if !hasExpectedFileSize(at: path, expectedSize: file.sizeBytes) {
                return false
            }
        }
        return true
    }

    private func hasExpectedFileSize(at url: URL, expectedSize: Int64) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return false
        }
        return size.int64Value == expectedSize
    }

    private func writeModelVerificationMarker() throws {
        try Self.modelVerificationSignature.write(
            to: Self.modelVerificationMarker,
            atomically: true,
            encoding: .utf8
        )
    }

    private func modelVerificationMarkerMatchesCurrentSpec() -> Bool {
        guard let marker = try? String(contentsOf: Self.modelVerificationMarker, encoding: .utf8) else {
            return false
        }
        return marker == Self.modelVerificationSignature
    }

    private func verifySHA256(of fileURL: URL, expected: String, label: String) throws {
        let actual = try sha256(of: fileURL)
        guard actual == expected else {
            throw SetupError.checksumMismatch("\(label) expected \(expected), got \(actual)")
        }
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hash = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                break
            }
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func processEnvironment(includePythonInPath: Bool) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["MACSTRAL_ENV_DIR"] = Self.envDir.path
        env["MACSTRAL_MODEL_DIR"] = Self.modelDir.path
        if includePythonInPath {
            let pythonBinDir = Self.pythonBinary.deletingLastPathComponent().path
            if let currentPath = env["PATH"], !currentPath.isEmpty {
                env["PATH"] = "\(pythonBinDir):\(currentPath)"
            } else {
                env["PATH"] = pythonBinDir
            }
        }
        return env
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
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
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            Task { @MainActor in
                guard activeDownloadTask?.taskIdentifier == downloadTask.taskIdentifier else {
                    try? FileManager.default.removeItem(at: tmp)
                    return
                }
                activeDownloadTask = nil
                activeDownloadID = nil
                activeDownloadContinuation?.resume(returning: tmp)
                activeDownloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                guard activeDownloadTask?.taskIdentifier == downloadTask.taskIdentifier else { return }
                activeDownloadTask = nil
                activeDownloadID = nil
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
            guard activeDownloadTask?.taskIdentifier == downloadTask.taskIdentifier else { return }
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
                guard activeDownloadTask?.taskIdentifier == task.taskIdentifier else { return }
                activeDownloadTask = nil
                activeDownloadID = nil
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
    case pythonValidationFailed(String)
    case missingResource(String)
    case serverStartFailed(String)
    case downloadFailed(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .pipInstallFailed(let msg): return "Dependency install failed: \(msg)"
        case .pythonValidationFailed(let msg): return "Python runtime validation failed: \(msg)"
        case .missingResource(let msg): return msg
        case .serverStartFailed(let msg): return "Server start failed: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .checksumMismatch(let msg): return "Checksum mismatch: \(msg)"
        }
    }
}
