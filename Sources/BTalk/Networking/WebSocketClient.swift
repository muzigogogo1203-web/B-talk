import Foundation

/// Generic WebSocket client wrapping URLSessionWebSocketTask.
actor WebSocketClient {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    private var onMessage: (@Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)?
    private var onDisconnect: (@Sendable (Error?) -> Void)?

    func connect(
        to url: URL,
        headers: [String: String] = [:],
        onMessage: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void,
        onDisconnect: @escaping @Sendable (Error?) -> Void
    ) {
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        receiveNext()
    }

    func send(text: String) async throws {
        guard let task = task else { throw WebSocketError.notConnected }
        try await task.send(.string(text))
    }

    func send(data: Data) async throws {
        guard let task = task else { throw WebSocketError.notConnected }
        try await task.send(.data(data))
    }

    func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure) {
        task?.cancel(with: code, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            Task {
                guard let self = self else { return }
                let handler = await self.onMessage
                let disconnectHandler = await self.onDisconnect
                switch result {
                case .success(let message):
                    handler?(.success(message))
                    await self.receiveNext()
                case .failure(let error):
                    handler?(.failure(error))
                    disconnectHandler?(error)
                }
            }
        }
    }
}

enum WebSocketError: Error, LocalizedError {
    case notConnected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket not connected"
        case .invalidResponse: return "Invalid WebSocket response"
        }
    }
}
