//
//  LinuxAsyncBytesShim.swift  (ใช้เฉพาะการรันทดสอบบน Linux — ไม่ได้อยู่ในตัวแอป)
//
//  บน Linux (swift-corelibs-foundation) ยังไม่มี `URLSession.bytes(for:)`
//  ซึ่งแอปใช้สตรีม SSE บน iOS ไฟล์นี้จึงเติมความสามารถนั้นให้ "เฉพาะตอนรัน E2E ในแซนด์บล็อก"
//  โดยยังคงส่งข้อมูลเป็น "ก้อนตามที่ TCP มาถึง" จริง (ใช้ URLSessionDataDelegate)
//  เพื่อให้การทดสอบครอบคลุมการประกอบบรรทัดข้าม packet — ตัวโค้ดแอปไม่ถูกแก้
//
//  บน macOS/iOS ไฟล์นี้จะถูกคอมไพล์เป็นโมฆะ (ทั้งไฟล์อยู่ใน #if !canImport(Darwin))
//

#if !canImport(Darwin)
import Foundation
import FoundationNetworking

/// ลำดับไบต์แบบ async ที่ส่งต่อข้อมูลเป็นก้อน Data ตามที่มาถึง
final class LinuxAsyncBytes: AsyncSequence, @unchecked Sendable {
    typealias Element = UInt8

    private let stream: AsyncThrowingStream<Data, Error>

    init(stream: AsyncThrowingStream<Data, Error>) {
        self.stream = stream
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(inner: stream.makeAsyncIterator())
    }

    struct Iterator: AsyncIteratorProtocol {
        private var inner: AsyncThrowingStream<Data, Error>.Iterator
        private var buffer: [UInt8] = []
        private var index = 0

        init(inner: AsyncThrowingStream<Data, Error>.Iterator) {
            self.inner = inner
        }

        mutating func next() async throws -> UInt8? {
            while index >= buffer.count {
                guard let data = try await inner.next() else { return nil }
                buffer = [UInt8](data)
                index = 0
                if buffer.isEmpty { continue }
            }
            let byte = buffer[index]
            index += 1
            return byte
        }
    }
}

/// ตัวรับข้อมูลจาก URLSessionDataDelegate แล้วส่งต่อเป็น Data ทีละก้อน
final class StreamingSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    private var pendingResponse: URLResponse?
    private var pendingResponseError: Error?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var session: URLSession?

    func makeStream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.session?.invalidateAndCancel()
            }
        }
    }

    /// ผลลัพธ์ที่พร้อมแล้ว (ถ้ามี) — แยกออกมาเพื่อไม่ให้เรียก lock ใน async context
    private enum Ready {
        case response(URLResponse)
        case failure(Error)
    }

    private func takeReady() -> Ready? {
        lock.lock()
        defer { lock.unlock() }
        if let response = pendingResponse { return .response(response) }
        if let error = pendingResponseError { return .failure(error) }
        return nil
    }

    func awaitResponse(session: URLSession) async throws -> URLResponse {
        lock.lock()
        self.session = session
        lock.unlock()

        if let ready = takeReady() {
            switch ready {
            case .response(let response): return response
            case .failure(let error): throw error
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let response = pendingResponse {
                lock.unlock()
                continuation.resume(returning: response)
                return
            }
            if let error = pendingResponseError {
                lock.unlock()
                continuation.resume(throwing: error)
                return
            }
            responseContinuation = continuation
            lock.unlock()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        pendingResponse = response
        let waiter = responseContinuation
        responseContinuation = nil
        lock.unlock()
        waiter?.resume(returning: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let sink = continuation
        lock.unlock()
        sink?.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let sink = continuation
        continuation = nil
        let waiter = responseContinuation
        responseContinuation = nil
        if let error = error {
            pendingResponseError = error
        }
        lock.unlock()

        if let error = error {
            waiter?.resume(throwing: error)
            sink?.finish(throwing: error)
        } else {
            sink?.finish()
        }
        session.finishTasksAndInvalidate()
    }
}

extension URLSession {
    /// แทนที่ URLSession.bytes(for:) บน Linux เพื่อการทดสอบ (ดูคอมเมนต์หัวไฟล์)
    func bytes(for request: URLRequest) async throws -> (LinuxAsyncBytes, URLResponse) {
        let delegate = StreamingSessionDelegate()
        let configuration = (self.configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
        let streamingSession = URLSession(configuration: configuration,
                                          delegate: delegate,
                                          delegateQueue: nil)
        let stream = delegate.makeStream()
        let task = streamingSession.dataTask(with: request)
        task.resume()
        let response = try await delegate.awaitResponse(session: streamingSession)
        return (LinuxAsyncBytes(stream: stream), response)
    }
}
#endif
