import Foundation
import OpenTelemetryApi
import OpenTelemetryConcurrency
import OpenTelemetrySdk
import ResourceExtension
import UUIDV7

typealias OpenTelemetry = OpenTelemetryConcurrency.OpenTelemetry

private struct IduraIdGenerator: IdGenerator {
  let randomIdGenerator = RandomIdGenerator()
  func generateSpanId() -> OpenTelemetryApi.SpanId {
    return randomIdGenerator.generateSpanId()
  }

  func generateTraceId() -> OpenTelemetryApi.TraceId {
    return TraceId(fromHexString: UUIDV7().uuidString.replacing("-", with: ""))
  }
}

internal struct URLRequestSetter: Setter {
  private init() {}
  internal static let instance = URLRequestSetter()
  func set(carrier: inout [String: String], key: String, value: String) {
    carrier[key] = value
  }
}

extension String {
  fileprivate func uppercaseFirst() -> String {
    return prefix(1).uppercased() + self.lowercased().dropFirst()
  }

  fileprivate mutating func uppercaseFirst() {
    self = self.uppercaseFirst()
  }
}

private struct IduraSpan: Encodable {
  let name: String
  let startTime: Int
  let endTime: Int
  let parentId: String
  let spanKind: String
  let status: String
  let attributes: [String: String]
  let context: [String: String?]
}

private class HeimdallExporter: SpanExporter {
  private let endpoint: URL

  init(_ endpoint: URL) {
    self.endpoint = endpoint
  }

  func shutdown(explicitTimeout: TimeInterval?) {}

  func flush(explicitTimeout: TimeInterval?) -> OpenTelemetrySdk.SpanExporterResultCode {
    return .success
  }

  private func toMs(date: Date) -> Int {
    return Int(date.timeIntervalSince1970 * 1000)
  }

  func export(spans: [OpenTelemetrySdk.SpanData], explicitTimeout: TimeInterval?)
    -> OpenTelemetrySdk.SpanExporterResultCode
  {
    let jsonEncoder = JSONEncoder()

    let spans = spans.map { spanData in
      let duration = toMs(date: spanData.endTime) - toMs(date: spanData.startTime)

      var attributes = spanData.attributes
      attributes.merge(spanData.resource.attributes) { first, _ in first }
      attributes["_duration"] = AttributeValue(duration)
      if case Status.error(let description) = spanData.status {
        attributes["error.message"] = AttributeValue(description)
      }

      return IduraSpan(
        name: spanData.name,
        startTime: toMs(date: spanData.startTime),
        endTime: toMs(date: spanData.endTime),
        parentId: (spanData.parentSpanId ?? SpanId.invalid).hexString,
        spanKind: spanData.kind.rawValue.uppercaseFirst(),
        status: spanData.status.name.uppercaseFirst(),
        attributes: attributes.mapValues { value in
          value.description
        },
        context: [
          "spanId": spanData.spanId.hexString,
          "traceId": spanData.traceId.hexString,
        ]
      )
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let explicitTimeout {
      request.timeoutInterval = explicitTimeout
    }

    do {
      request.httpBody = try jsonEncoder.encode(spans)
    } catch {
      return .failure
    }

    let semaphore = DispatchSemaphore(value: 0)
    var status: SpanExporterResultCode = .failure

    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error {
        print("Error while sending metrics \(error)")
        status = .failure
      }
      if let httpResponse = response as? HTTPURLResponse {
        if httpResponse.statusCode == 201 {
          status = .success
        } else {
          print("Error while sending metrics \(httpResponse.statusCode)")
          status = .failure
        }
      }

      semaphore.signal()
    }.resume()
    // Exporting runs on a separate thread, so we can safely spin our wheels until the task is
    // complete. Inspired by https://github.com/open-telemetry/opentelemetry-swift/blob/78063d279b0761e05d3e9a3ab789a85f25ec99f3/Sources/Exporters/Zipkin/ZipkinTraceExporter.swift
    semaphore.wait()

    return status
  }
}

func initTelemetry(serverAddress: String, version: String) -> (TracerProvider, TextMapPropagator) {
  let tracerProvider = TracerProviderBuilder()
    .add(
      spanProcessor: BatchSpanProcessor(
        spanExporter: HeimdallExporter(URL(string: "https://telemetry.svc.criipto.com/v1/trace")!))
    )
    .with(idGenerator: IduraIdGenerator())
    .with(
      resource: DefaultResources().get().merging(
        other: Resource(attributes: [
          "server.address": AttributeValue.string(serverAddress),
          "idura.sdk.version": AttributeValue.string(version),
        ]))
    )
    .build()

  let propagator = W3CTraceContextPropagator()

  // IMPORTANT: DO NOT use OpenTelemetry.instance here, since it pollutes the global instance, which
  // may be used in consuming apps as well.
  // Swift only allows one version of a package to exist in a project, so if a consuming app also
  // depends on OTEL, we don't want to pollute the global instance with our trace provider.
  // See https://forums.swift.org/t/swift-package-dependency-managment/70948/7
  return (tracerProvider, propagator)
}

extension SpanBuilderBase {
  public func runWithSpan<T>(_ operation: (any SpanBase) async throws -> T) async rethrows -> T {
    let createdSpan = self.startSpan()
    defer {
      createdSpan.end()
    }

    do {
      let result = try await operation(createdSpan)
      createdSpan.status = .ok
      return result
    } catch {
      createdSpan.status = .error(description: error.localizedDescription)
      createdSpan.recordException(error)
      throw error
    }
  }
}
