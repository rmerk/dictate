import Foundation

struct ConfigService {
    static let shared = ConfigService()

    let configPath: String

    init(configPath: String = NSString(
            string: "~/Library/RCLI/config").expandingTildeInPath) {
        self.configPath = configPath
    }

    func read(key: String) -> String? {
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        for line in contents.components(separatedBy: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == key {
                return String(parts[1])
            }
        }
        return nil
    }

    func write(key: String, value: String) throws {
        let fm = FileManager.default
        var lines: [String] = []

        if fm.fileExists(atPath: configPath) {
            let contents = try String(contentsOfFile: configPath, encoding: .utf8)
            lines = contents.components(separatedBy: "\n")
        } else {
            let dir = (configPath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let prefix = "\(key)="
        var replaced = false
        for i in lines.indices {
            if lines[i].hasPrefix(prefix) {
                lines[i] = "\(key)=\(value)"
                replaced = true
                break
            }
        }
        if !replaced {
            while lines.last?.isEmpty == true { lines.removeLast() }
            lines.append("\(key)=\(value)")
        }

        let output = lines.joined(separator: "\n") + "\n"
        try output.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}
