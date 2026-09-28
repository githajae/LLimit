import Foundation
import Darwin

/// Check callback availability without signalling processes or contacting
/// another login server's /cancel endpoint. Only an owned login may be cancelled.
enum PortUtil {
    static func requireAvailable(_ port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            throw NSError(domain: "LLimit.Login", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Sign-in port \(port) is unavailable. Finish or close the other sign-in window, then retry. LLimit has not stopped any other app."
            ])
        }
    }
}
