import Foundation

/// Legacy placeholder delegate kept for compatibility with previous project setups that
/// expected an `SSLPinningDelegate` file to exist. The current controller communicates over
/// the local network using plain HTTP, so no TLS pinning is required. When the app is built
/// with HTTPS in the future, this type can be expanded to perform real certificate checks.
final class SSLPinningDelegate: NSObject, URLSessionDelegate {
    /// Simply defers to the system's default TLS handling because we currently talk to the
    /// controller over an unauthenticated local network connection.
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}
