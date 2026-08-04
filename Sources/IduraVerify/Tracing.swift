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

func initTelemetry(serverAddress: String, version: String) -> (TracerProviderSdk, TextMapPropagator)
{
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
          "service.name": AttributeValue.string("idura-verify-ios"),
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

@MainActor
extension SpanBuilderBase {
  /// Start the span built by `self`, run `operation` inside it, and end the span when it
  /// returns or throws. The span's status is set to `.ok` on success and `.error` on
  /// failure, and any thrown error is recorded as an exception on the span.
  ///
  /// `@MainActor` because IduraVerify is main-actor-isolated and the closure body needs
  /// to capture main-actor state (the SDK's mutable config + the current eID).
  func runWithSpan<T>(
    _ operation: @MainActor (any SpanBase) async throws -> T
  ) async rethrows -> T {
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
