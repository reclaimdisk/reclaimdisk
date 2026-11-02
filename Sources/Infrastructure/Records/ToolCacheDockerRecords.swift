import Catalog
import Darwin
import Foundation
import os
import SharedKernel

/// Reads Docker once per instance. Later calls return that reading, including a timeout or a parse failure.
final class LiveDockerRecords: DockerRecords, Sendable {
    private let home: CanonicalPath
    private let cache = OSAllocatedUnfairLock<DockerReading?>(initialState: nil)

    init(home: CanonicalPath) { self.home = home }

    func read() -> DockerReading {
        cache.withLock { cached in
            if let cached { return cached }
            let reading = load()
            cached = reading
            return reading
        }
    }

    private func load() -> DockerReading {
        let directories = binaryDirectories(home: home)
        guard let docker = ToolCacheCommand.executable(named: "docker", in: directories) else { return .notInstalled }
        let environment = ["HOME": home.raw, "PATH": directories.joined(separator: ":")]
        let system: String
        let imageList: String
        let volumeList: String
        let containers: String
        switch query(docker: docker, arguments: ["system", "df", "--format", "json"], name: "docker system df", environment: environment) {
        case .output(let text): system = text
        case .stop(let reading): return reading
        }
        switch query(docker: docker, arguments: ["image", "ls", "--format", "json"], name: "docker image ls", environment: environment) {
        case .output(let text): imageList = text
        case .stop(let reading): return reading
        }
        switch query(docker: docker, arguments: ["volume", "ls", "--format", "json"], name: "docker volume ls", environment: environment) {
        case .output(let text): volumeList = text
        case .stop(let reading): return reading
        }
        switch query(docker: docker, arguments: ["ps", "-a", "--no-trunc", "--format", "json"], name: "docker ps", environment: environment) {
        case .output(let text): containers = text
        case .stop(let reading): return reading
        }
        guard let summary = DockerOutput.systemDF(system) else { return .unparseable("docker system df output could not be read") }
        guard let images = DockerOutput.images(imageList, containers: containers) else {
            return .unparseable("docker image ls output could not be read")
        }
        guard let volumes = DockerOutput.volumes(volumeList, containers: containers) else {
            return .unparseable("docker volume ls output could not be read")
        }
        return .read(DockerSnapshot(
            buildCacheReclaimable: summary.buildCacheReclaimable, images: images, volumes: volumes,
            anonymousVolumesReclaimable: summary.volumesReclaimable, diskFile: diskFile(home: home)
        ))
    }
}

private enum DockerQuery {
    case output(String)
    case stop(DockerReading)
}

private func query(docker: String, arguments: [String], name: String, environment: [String: String]) -> DockerQuery {
    guard let output = ToolCacheCommand.run(executable: docker, arguments: arguments, environment: environment) else {
        return .stop(.notResponding("couldn't start \(name)"))
    }
    if output.timedOut || output.status != 0 { return .stop(.notResponding(failureReason(output, command: name))) }
    return .output(output.standardOutput)
}

private func failureReason(_ output: ToolCacheCommand.Output, command: String) -> String {
    if output.timedOut { return "timed out after 10 s" }
    let error = output.standardError.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !error.isEmpty { return String(error.prefix(300)) }
    return "\(command) exited with status \(output.status)"
}

private func binaryDirectories(home: CanonicalPath) -> [String] {
    var directories = ["/usr/local/bin", "/opt/homebrew/bin"]
    if let bin = home.appending(".docker")?.appending("bin") { directories.append(bin.raw) }
    directories.append("/Applications/Docker.app/Contents/Resources/bin")
    return directories
}

/// `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`. Allocated size is `st_blocks` × 512.
private func diskFile(home: CanonicalPath) -> DockerDiskFile? {
    let components = ["Library", "Containers", "com.docker.docker", "Data", "vms", "0", "data", "Docker.raw"]
    var path = home
    for component in components {
        guard let next = path.appending(component) else { return nil }
        path = next
    }
    var info = stat()
    guard lstat(path.raw, &info) == 0 else { return nil }
    let blocks: UInt64 = info.st_blocks > 0 ? UInt64(info.st_blocks) : 0
    let maximum: UInt64 = info.st_size > 0 ? UInt64(info.st_size) : 0
    let (allocated, overflowed) = blocks.multipliedReportingOverflow(by: 512)
    return DockerDiskFile(path: path, allocated: ByteCount(overflowed ? .max : allocated), maximum: ByteCount(maximum))
}
