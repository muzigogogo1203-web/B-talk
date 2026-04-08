import Foundation

/// Server-Sent Events client for streaming LLM responses.
/// Request: Content-Type: application/json with "stream": true in body
/// Response: text/event-stream parsed line by line
struct SSEClient {
    /// Stream SSE events from a POST endpoint.
    /// - Returns: AsyncStream of (event: String?, data: String) tuples
    static func stream(
        url: URL,
        headers: [String: String],
        body: Data
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = body
                // Request headers: always application/json, NOT text/event-stream
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: HTTPError.invalidResponse)
                        return
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        // Read error body for diagnostics (up to 1KB)
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 1000 { break }
                        }
                        continuation.finish(throwing: HTTPError.statusCode(httpResponse.statusCode, errorBody))
                        return
                    }

                    // Parse SSE frames line by line
                    var eventType: String? = nil
                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            dataLines.append(data)
                        } else if line.isEmpty {
                            // Dispatch the accumulated event
                            if !dataLines.isEmpty {
                                let event = SSEEvent(
                                    event: eventType,
                                    data: dataLines.joined(separator: "\n")
                                )
                                continuation.yield(event)
                            }
                            eventType = nil
                            dataLines = []
                        }
                        // Ignore comment lines (":") and other lines
                    }
                    // Flush any remaining data lines not terminated by an empty line
                    // (e.g. Gemini SSE sends consecutive data: lines without blank-line separators)
                    for dataLine in dataLines {
                        continuation.yield(SSEEvent(event: eventType, data: dataLine))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

struct SSEEvent: Sendable {
    let event: String?  // e.g. "message_start", "content_block_delta", "message_stop", "ping", "error"
    let data: String
}
