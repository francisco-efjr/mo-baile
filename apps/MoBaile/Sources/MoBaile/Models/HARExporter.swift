import Foundation

public enum HARExporter {
    public static func generateHAR(from events: [NetworkEvent]) -> Data? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let entries: [[String: Any]] = events.map { event in
            var postData: [String: Any]? = nil
            if !event.requestBody.isEmpty {
                let mime = event.requestHeaders.first { $0.key.lowercased() == "content-type" }?.value ?? "application/json"
                postData = [
                    "mimeType": mime,
                    "text": event.requestBody
                ]
            }

            var content: [String: Any] = [
                "size": event.responseBody.utf8.count,
                "mimeType": event.responseHeaders.first { $0.key.lowercased() == "content-type" }?.value ?? "application/json",
            ]
            if !event.responseBody.isEmpty {
                content["text"] = event.responseBody
            }

            let duration = event.durationMs ?? 0

            var reqDict: [String: Any] = [
                "method": event.method,
                "url": event.url,
                "httpVersion": event.protocol.isEmpty ? "HTTP/1.1" : event.protocol,
                "headers": event.requestHeaders.map { ["name": $0.key, "value": $0.value] },
                "queryString": [],
                "cookies": [],
                "headersSize": -1,
                "bodySize": event.requestBody.utf8.count
            ]
            if let postData {
                reqDict["postData"] = postData
            }

            let respDict: [String: Any] = [
                "status": event.statusCode ?? 0,
                "statusText": event.statusText.isEmpty ? (event.statusCode == 200 ? "OK" : "") : event.statusText,
                "httpVersion": event.protocol.isEmpty ? "HTTP/1.1" : event.protocol,
                "headers": event.responseHeaders.map { ["name": $0.key, "value": $0.value] },
                "cookies": [],
                "content": content,
                "redirectURL": "",
                "headersSize": -1,
                "bodySize": event.responseBody.utf8.count
            ]

            let entry: [String: Any] = [
                "startedDateTime": isoFormatter.string(from: event.timestamp),
                "time": duration,
                "request": reqDict,
                "response": respDict,
                "cache": [String: Any](),
                "timings": [
                    "send": 0,
                    "wait": duration,
                    "receive": 0
                ]
            ]
            return entry
        }

        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": [
                    "name": "Mo baile",
                    "version": "2.0"
                ],
                "entries": entries
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .sortedKeys])
    }
}
