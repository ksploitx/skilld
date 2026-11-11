// MockURLProtocol.swift
// skilldTests
//
// A URLProtocol subclass that intercepts all requests and returns
// canned responses. Inject via:
//
//   let config = URLSessionConfiguration.ephemeral
//   config.protocolClasses = [MockURLProtocol.self]
//   let session = URLSession(configuration: config)
//
// Then set MockURLProtocol.requestHandler before each test.

import Foundation

final class MockURLProtocol: URLProtocol {

    /// Set this in each test before making a request.
    /// Return `(response, data)` or throw to simulate a network error.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        true  // intercept everything
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

extension MockURLProtocol {

    /// Build a URLSession wired to MockURLProtocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Convenience: return a successful JSON response.
    static func respond(json: Data, statusCode: Int = 200, url: URL = URL(string: "http://localhost")!) -> (HTTPURLResponse, Data?) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, json)
    }

    /// Convenience: return an HTTP error response.
    static func respond(statusCode: Int, body: String = "", url: URL = URL(string: "http://localhost")!) -> (HTTPURLResponse, Data?) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (response, body.data(using: .utf8))
    }
}

