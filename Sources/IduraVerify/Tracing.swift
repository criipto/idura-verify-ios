import Foundation
import OpenTelemetryApi
import OpenTelemetryConcurrency
import OpenTelemetryProtocolExporterCommon
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
  let exportTimeout: TimeInterval = 10

  // `OtlpHttpExporterBase.createRequest` never applies `OtlpConfiguration.timeout` to the
  // `URLRequest`, so the only way to bound a hung export is at the session level.
  let sessionConfiguration: URLSessionConfiguration = .ephemeral
  sessionConfiguration.urlCache = nil
  sessionConfiguration.timeoutIntervalForRequest = exportTimeout

  let tracerProvider = TracerProviderBuilder()
    .add(
      spanProcessor: BatchSpanProcessor(
        spanExporter: OtlpHttpTraceExporter(
          endpoint: URL(string: "https://telemetry.idura.app/v1/traces")!,
          config: OtlpConfiguration(timeout: exportTimeout),
          httpClient: BaseHTTPClient(
            session: URLSession(configuration: sessionConfiguration))),
        exportTimeout: exportTimeout)
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

/// Shut the tracer provider down off the calling thread.
///
/// `TracerProviderSdk.shutdown()` drains the batch processor synchronously — it waits on the
/// worker's operation queue while pending spans are serialised and compressed. It's called from
/// `IduraVerify.deinit`, which is nonisolated and runs on whichever thread drops the last
/// reference, so doing that work inline can block the main thread.
///
/// `nonisolated(unsafe)` because `TracerProviderSdk` isn't `Sendable`. Safe here because the
/// caller is being deallocated and hands over its only reference, so nothing else can reach the
/// provider concurrently.
func drainTelemetry(_ tracerProvider: TracerProviderSdk) {
  nonisolated(unsafe) let tracerProvider = tracerProvider
  DispatchQueue.global(qos: .utility).async {
    tracerProvider.shutdown()
  }
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
