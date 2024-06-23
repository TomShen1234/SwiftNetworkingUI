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

struct AsyncDefaultProgressView: View {
    var body: some View {
        ProgressView("Loading...")
    }
}

struct AsyncDefaultErrorView: View {
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
public struct AsyncView<Data, Content: View, LoadingContent: View, ErrorContent: View>: View {
    var makeContent: (Data) -> Content
    var loadClosure: () async throws -> Data
    
    var loadingView: LoadingContent?
    
    typealias MakeErrorClosure = ((Error, @escaping () -> ()) -> ErrorContent)
    var makeErrorView: MakeErrorClosure?
    
    var reloadPublisher: AnyPublisher<Void, Never>?
    var unwrappedReloadPublisher: AnyPublisher<Void, Never> {
        // Unwrap it by replacing nil value with an empty publisher
        reloadPublisher ?? Empty().eraseToAnyPublisher()
    }
    
    public init(@ViewBuilder makeContent: @escaping (Data) -> Content, loadClosure: @escaping () async throws -> Data) where ErrorContent == EmptyView, LoadingContent == EmptyView {
        self.makeContent = makeContent
        self.loadClosure = loadClosure
        self.loadingState = .idle
        self.loadingView = nil
        self.makeErrorView = nil
    }
    
    internal init(reloadPublisher: AnyPublisher<Void, Never>? = nil, @ViewBuilder makeContent: @escaping (Data) -> Content, loadClosure: @escaping () async throws -> Data, loadingView: LoadingContent?, makeErrorView: MakeErrorClosure?) {
        self.reloadPublisher = reloadPublisher
        self.makeContent = makeContent
        self.loadClosure = loadClosure
        self.loadingState = .idle
        self.loadingView = loadingView
        self.makeErrorView = makeErrorView
    }
    
    @State private var loadingState = LoadingState<Data>.idle
    
    public var body: some View {
        LoadingStateView(state: loadingState) { downloadedContents in
            makeContent(downloadedContents)
        } makeProgressView: {
            Group {
                if let loadingView {
                    loadingView
                } else {
                    AsyncDefaultProgressView()
                }
            }
            .task { await loadData() }
        } makeErrorView: { error in
            if let makeErrorView {
                makeErrorView(error, reload)
            } else {
                AsyncDefaultErrorView(error: error, retryHandler: reload)
            }
        }
        .onReceive(unwrappedReloadPublisher, perform: reload)
    }
    
    private func reload() {
        Task {
            await loadData()
        }
    }
    
    private func loadData() async {
        if case .loading = loadingState {
            // Skip additional requests when it's already loading
            return
        }
        
        loadingState = .loading
        do {
            let content = try await loadClosure()
            loadingState = .loaded(content)
        } catch {
            loadingState = .failed(error)
        }
    }
}

public extension AsyncView {
    func reload(onReceive publisher: AnyPublisher<Void, Never>) -> AsyncView {
        .init(reloadPublisher: publisher, makeContent: self.makeContent, loadClosure: self.loadClosure, loadingView: self.loadingView, makeErrorView: self.makeErrorView)
    }
}

public extension AsyncView where LoadingContent == EmptyView {
    func customLoadingView<LV: View>(@ViewBuilder makeLoadingView: () -> LV) -> AsyncView<Data, Content, LV, ErrorContent> {
        .init(makeContent: self.makeContent, loadClosure: self.loadClosure, loadingView: makeLoadingView(), makeErrorView: self.makeErrorView)
    }
}

public extension AsyncView where ErrorContent == EmptyView {
    func customErrorView<EV: View>(@ViewBuilder makeErrorView: @escaping (Error, @escaping () -> ()) -> EV) -> AsyncView<Data, Content, LoadingContent, EV> {
        .init(makeContent: self.makeContent, loadClosure: self.loadClosure, loadingView: self.loadingView, makeErrorView: makeErrorView)
    }
}

// MARK: - Additional Endpoint Based Initializers
public extension AsyncView where ErrorContent == EmptyView, LoadingContent == EmptyView {
    init(downloadFrom request: URLRequest, decodeTo decodeType: Data.Type, @ViewBuilder makeContent: @escaping (Data) -> Content) where Data: Decodable {
        let loadClosure = {
            return try await URLSession.shared.data(for: request, responseType: decodeType.self)
        }
        self.init(makeContent: makeContent, loadClosure: loadClosure)
    }
    
    init<K>(downloadFrom endpoint: Endpoint<K, Data>, using data: K.RequestData, @ViewBuilder makeContent: @escaping (Data) -> Content) where Data: Decodable, K: EndpointKind {
        let loadClosure = {
            return try await URLSession.shared.data(for: endpoint, using: data)
        }
        self.init(makeContent: makeContent, loadClosure: loadClosure)
    }
    
    init<K>(downloadFrom endpoint: Endpoint<K, String>, using data: K.RequestData, @ViewBuilder makeContent: @escaping (String) -> Content) where Data == String, K: EndpointKind {
        let loadClosure = {
            return try await URLSession.shared.string(for: endpoint, using: data)
        }
        self.init(makeContent: makeContent, loadClosure: loadClosure)
    }
    
    init<K>(downloadFrom endpoint: Endpoint<K, Data>, @ViewBuilder makeContent: @escaping (Data) -> Content) where Data: Decodable, K: EndpointKind, K.RequestData == Void {
        self.init(downloadFrom: endpoint, using: (), makeContent: makeContent)
    }
    
    init<K>(downloadFrom endpoint: Endpoint<K, String>, @ViewBuilder makeContent: @escaping (String) -> Content) where Data == String, K: EndpointKind, K.RequestData == Void {
        self.init(downloadFrom: endpoint, using: (), makeContent: makeContent)
    }
}
