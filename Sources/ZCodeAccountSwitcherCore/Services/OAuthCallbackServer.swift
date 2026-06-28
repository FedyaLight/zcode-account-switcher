import Darwin
import Foundation

public final class OAuthCallbackServer {
    public let redirectURI: String

    private let socketFD: Int32
    private let queue = DispatchQueue(label: "com.zcode.account-switcher.oauth-callback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var pendingResult: Result<URL, Error>?
    private var didComplete = false
    private var didCloseSocket = false

    private init(socketFD: Int32, port: UInt16) {
        self.socketFD = socketFD
        self.redirectURI = "http://127.0.0.1:\(port)/oauth/callback"
    }

    deinit {
        closeSocket()
    }

    public static func start() async throws -> OAuthCallbackServer {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AccountError.oauthTokenResponse("Local OAuth callback socket failed: \(posixError())")
        }

        var reuse: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            close(fd)
            throw AccountError.oauthTokenResponse("Local OAuth callback socket setup failed: \(posixError())")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw AccountError.oauthTokenResponse("Local OAuth callback bind failed: \(posixError())")
        }

        guard listen(fd, 4) == 0 else {
            close(fd)
            throw AccountError.oauthTokenResponse("Local OAuth callback listen failed: \(posixError())")
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &boundLength)
            }
        }
        guard nameResult == 0 else {
            close(fd)
            throw AccountError.oauthTokenResponse("Local OAuth callback port lookup failed: \(posixError())")
        }

        let server = OAuthCallbackServer(socketFD: fd, port: UInt16(bigEndian: boundAddress.sin_port))
        server.startAcceptLoop()
        return server
    }

    public func waitForCallback(timeoutSeconds: UInt64 = 600) async throws -> URL {
        let timeout = Task { [weak self] in
            try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            self?.complete(.failure(AccountError.oauthTokenResponse("Waiting for browser login timed out.")))
        }
        defer { timeout.cancel() }
        return try await waitForCallbackOnce()
    }

    public func stop() {
        complete(.failure(AccountError.oauthTokenResponse("OAuth login was cancelled.")))
    }

    private func waitForCallbackOnce() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingResult {
                self.pendingResult = nil
                lock.unlock()
                continuation.resume(with: pendingResult)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func startAcceptLoop() {
        queue.async { [weak self] in
            guard let self else { return }
            while true {
                if self.isComplete { return }
                let client = accept(self.socketFD, nil, nil)
                if client < 0 {
                    if self.isComplete { return }
                    continue
                }
                self.handle(clientFD: client)
            }
        }
    }

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }

        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            recv(clientFD, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        guard count > 0,
              let request = String(bytes: buffer.prefix(count), encoding: .utf8),
              let callbackURL = Self.callbackURL(from: request)
        else {
            sendResponse(
                status: "404 Not Found",
                title: "Login failed",
                message: "OAuth callback URL was not recognized.",
                clientFD: clientFD
            )
            return
        }

        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let errorMessage = components?.queryItems?.first(where: { $0.name == "error_description" })?.value
            ?? components?.queryItems?.first(where: { $0.name == "error" })?.value
        let code = components?.queryItems?.first(where: { $0.name == "code" || $0.name == "authCode" })?.value

        if let errorMessage, !errorMessage.isEmpty {
            complete(.failure(AccountError.oauthTokenResponse(errorMessage)))
            sendResponse(
                status: "200 OK",
                title: "Login failed",
                message: "Z.ai returned a login error. You can close this page.",
                clientFD: clientFD
            )
            return
        }

        guard code?.isEmpty == false else {
            complete(.failure(AccountError.oauthMissingCode))
            sendResponse(
                status: "200 OK",
                title: "Login failed",
                message: "The OAuth callback did not include an authorization code.",
                clientFD: clientFD
            )
            return
        }

        complete(.success(callbackURL))
        sendResponse(
            status: "200 OK",
            title: "Login complete",
            message: "Authorization was received. You can close this page and return to ZCode Account Switcher.",
            clientFD: clientFD
        )
    }

    private var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didComplete
    }

    private func complete(_ result: Result<URL, Error>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        let continuation = continuation
        self.continuation = nil
        if continuation == nil {
            pendingResult = result
        }
        lock.unlock()

        if let continuation {
            continuation.resume(with: result)
        }
        closeSocket()
    }

    private func closeSocket() {
        lock.lock()
        guard !didCloseSocket else {
            lock.unlock()
            return
        }
        didCloseSocket = true
        let fd = socketFD
        lock.unlock()

        shutdown(fd, SHUT_RDWR)
        close(fd)
    }

    private func sendResponse(status: String, title: String, message: String, clientFD: Int32) {
        let body = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
        </head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;margin:0;display:grid;min-height:100vh;place-items:center;background:#f7f8fb;color:#17202a">
          <main style="max-width:520px;padding:28px;background:white;border:1px solid #e7e9ef;border-radius:14px;box-shadow:0 18px 45px rgba(20,26,40,.08)">
            <h1 style="font-size:22px;margin:0 0 12px">\(title)</h1>
            <p style="line-height:1.6;color:#53606f;margin:0">\(message)</p>
          </main>
        </body>
        </html>
        """
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        """
        var response = Data(header.utf8)
        response.append(bodyData)
        sendAll(response, to: clientFD)
    }

    private func sendAll(_ data: Data, to clientFD: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let result = send(clientFD, baseAddress.advanced(by: sent), rawBuffer.count - sent, 0)
                if result <= 0 { return }
                sent += result
            }
        }
    }

    private static func callbackURL(from request: String) -> URL? {
        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }
        let target = parts[1]
        guard target.hasPrefix("/oauth/callback") else {
            return nil
        }
        return URL(string: "http://127.0.0.1\(target)")
    }

    private static func posixError() -> String {
        String(cString: strerror(errno))
    }
}
