import Foundation
import SwiftUI
import Combine

// MARK: - Loadable View

enum LoadingState<Value> {
    case idle
    case loading
    case failed(Error)
    case loaded(Value)
}

/// The core of `AsyncContentView`.
/// This view renders different content based on the `LoadingState` parameter.
struct LoadingStateView<OutputType, ProgressViewType: View, ErrorViewType: View, OutputViewType: View>: View {
    init(state: LoadingState<OutputType>,
         @ViewBuilder makeOutputView: @escaping (OutputType) -> OutputViewType,
         @ViewBuilder makeProgressView: @escaping () -> ProgressViewType,
         @ViewBuilder makeErrorView: @escaping (Error) -> ErrorViewType) {
        self.state = state
        self.makeProgressView = makeProgressView
        self.makeErrorView = makeErrorView
        self.makeOutputView = makeOutputView
    }
    
    /// Initialize `LoadingStateView` with default error and loading view
    init(state: LoadingState<OutputType>,
         @ViewBuilder makeOutputView: @escaping (OutputType) -> OutputViewType,
         onErrorRetry: @escaping () -> ())
    where ErrorViewType == ErrorView, ProgressViewType == DefaultProgressView {
        self.state = state
        self.makeProgressView = { DefaultProgressView() }
        self.makeErrorView = { error in ErrorView(error: error, retryHandler: onErrorRetry) }
        self.makeOutputView = makeOutputView
    }
    
    var state: LoadingState<OutputType>
    
    var makeProgressView: () -> ProgressViewType
    var makeErrorView: (Error) -> ErrorViewType
    var makeOutputView: (OutputType) -> OutputViewType
    
    @ViewBuilder var body: some View {
        switch state {
        case .idle, .loading:
            makeProgressView()
        case .failed(let error):
            makeErrorView(error)
        case .loaded(let output):
            makeOutputView(output)
        }
    }
}

struct DefaultProgressView: View {
    var body: some View {
        ProgressView("Loading...")
    }
}

struct ErrorView: View {
    var error: Error
    var retryHandler: () -> ()
    
    var body: some View {
        VStack {
            Text("Error")
            Text(error.localizedDescription)
            Button("Retry", action: retryHandler)
        }
    }
}

// MARK: - Async Content View
/// A view that loads data asynchronously from an async/await closure, and displays a content view when finished
public struct AsyncView<Data, Content: View>: View {
    @ViewBuilder public var makeContent: (Data) -> Content
    public var loadClosure: () async throws -> Data
    
    public init(makeContent: @escaping (Data) -> Content, loadClosure: @escaping () async throws -> Data) {
        self.makeContent = makeContent
        self.loadClosure = loadClosure
        self.loadingState = .idle
    }
    
    @State private var loadingState = LoadingState<Data>.idle
    
    public var body: some View {
        LoadingStateView(state: loadingState) { downloadedContents in
            makeContent(downloadedContents)
        } makeProgressView: {
            ProgressView("Loading...").task { await loadData() }
        } makeErrorView: { error in
            ErrorView(error: error) {
                Task {
                    await loadData()
                }
            }
        }
    }
    
    private func loadData() async {
        loadingState = .loading
        do {
            let content = try await loadClosure()
            loadingState = .loaded(content)
        } catch {
            loadingState = .failed(error)
        }
    }
}

// MARK: - Additional Endpoint Based Initializers
extension AsyncView {
    public init(downloadFrom request: URLRequest, decodeTo decodeType: Data.Type, decoder: JSONDecoder = .init(), makeContent: @escaping (Data) -> Content) where Data: Decodable {
        let loadClosure = {
            return try await URLSession.shared.data(for: request, responseType: decodeType.self, decoder: decoder)
        }
        self.init(makeContent: makeContent, loadClosure: loadClosure)
    }
    
    public init<K>(downloadFrom endpoint: Endpoint<K, Data>, using data: K.RequestData, decoder: JSONDecoder = .init(), makeContent: @escaping (Data) -> Content) where Data: Decodable, K: EndpointKind {
        let loadClosure = {
            return try await URLSession.shared.data(for: endpoint, using: data, decoder: decoder)
        }
        self.init(makeContent: makeContent, loadClosure: loadClosure)
    }
    
    public init<K>(downloadFrom endpoint: Endpoint<K, String>, using data: K.RequestData, makeContent: @escaping (String) -> Content) where Data == String, K: EndpointKind {
        let loadClosure = {
            return try await URLSession.shared.string(for: endpoint, using: data)
        }
        self.init(makeContent: makeContent, loadClosure: loadClosure)
    }
    
    public init<K>(downloadFrom endpoint: Endpoint<K, Data>, decoder: JSONDecoder = .init(), makeContent: @escaping (Data) -> Content) where Data: Decodable, K: EndpointKind, K.RequestData == Void {
        self.init(downloadFrom: endpoint, using: (), decoder: decoder, makeContent: makeContent)
    }
    
    public init<K>(downloadFrom endpoint: Endpoint<K, String>, makeContent: @escaping (String) -> Content) where Data == String, K: EndpointKind, K.RequestData == Void {
        self.init(downloadFrom: endpoint, using: (), makeContent: makeContent)
    }
}
