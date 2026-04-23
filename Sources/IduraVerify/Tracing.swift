import Foundation
import OpenTelemetryApi
import OpenTelemetryConcurrency
import OpenTelemetryProtocolExporterHttp
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

func initTelemetry(serverAddress: String, version: String) -> (TracerProvider, TextMapPropagator) {
  let tracerProvider = TracerProviderBuilder()
    .add(
      spanProcessor: BatchSpanProcessor(
        spanExporter: OtlpHttpTraceExporter(
          endpoint: URL(string: "https://telemetry.idura.app/v1/traces")!))
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
