import Foundation
import Security

final class SSLPinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedCertificates: [Data]

    override init() {
        if let urls = Bundle.main.urls(forResourcesWithExtension: "cer", subdirectory: nil) {
            self.pinnedCertificates = urls.compactMap { try? Data(contentsOf: $0) }
        } else {
            self.pinnedCertificates = []
        }
        super.init()
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard !pinnedCertificates.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let policies = NSMutableArray()
        policies.add(SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString))
        SecTrustSetPolicies(serverTrust, policies)

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let serverCertificatesCount = SecTrustGetCertificateCount(serverTrust)
        for index in 0..<serverCertificatesCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else { continue }
            let serverCertificateData = SecCertificateCopyData(certificate) as Data
            if pinnedCertificates.contains(serverCertificateData) {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }

        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
