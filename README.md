# SwiftNetworkingUI

This is a library that automates downloading JSON data from REST APIs and displays it in a SwiftUI View.

## Basic Usage

Let's say that `http://127.0.0.1/` downloads the following JSON:

```json
[
    {
        "name": "Tom",
        "age": 20,
        "id": "D7F647B9-A0E3-4B13-96AC-84F50110A11D",
    },
    ...
]
```

First we need a `Codable` struct that describes the data model:

```swift
struct SimpleModel: Codable, Identifiable {
    var id: UUID
    var name: String
    var age: Int
}
```

It is then as simple as this to download and display the data on screen:

```swift
var body: some View {
    let url = URL(string: "http://127.0.0.1/")!
    let request = URLRequest(url: url)
    AsyncView(downloadFrom: request, decodeTo: [SimpleModel].self) { people in
        List {
            ForEach(people) { person in
                Text("\(person.name) \(person.age)")
            }
        }
    }
}
```

There are 3 modifiers for this view:

- `customLoadingView` - Overrides the default activity indicator while loading
- `customErrorView` - Overrides the default error view
- `reload(onReceive:)` - Takes a publisher (type `Void`, error `Never`), and reloads the view whenever the publisher publishes a value.

This view uses a custom function in an extension of `URLSession`, which can also be used directly in the code:

```swift
func data<T>(for request: URLRequest, responseType: T.Type = T.self, decoder: JSONDecoder = .init()) async throws -> T where T: Decodable
```

## Endpoints (optional)

This library supports more than just downloading from `URLRequest`s. There is also an `Endpoint` type that leverages generics to automate request preprocessing.

```swift
struct Endpoint<Kind: EndpointKind, Response: Decodable>
```

The only parameter required by the endpoint is an `URL` to create the `URLRequest`. But the kind of endpoint and the response type has to be mentioned via generic types.

There are several kinds for an endpoint (all as subtypes of `EndpointKinds`):

| Type | HTTP Method | Authentication | Object Encoding |
| ---- | ----------- | -------------- |
| `Public` | `GET` | None | No |
| `BasicGet` | `GET` | Basic | No |
| `BearerGet` | `GET` | Bearer | No |
| `PublicUpload` | `POST` | None | Yes |
| `Upload` | `POST` | Bearer | Yes |
| `Edit` | `PUT` | Bearer | Yes |
| `Delete` | `DELETE` | Bearer | Yes |

It is possible to implement custom endpoint kinds too, simply create a enum that conforms to `EndpointKind` protocol.

For a simple `GET` operation (use `Public` as an example), create an endpoint like this:

```swift
var endpoint: Endpoint<EndpointKinds.Public, [SimpleModel]> {
    Endpoint(url: URL(string: "http://127.0.0.1:8080/")!)
}
```

`AsyncView` has built-in support for the 3 `GET` based endpoint kinds with no object encoding:

```swift
AsyncView(downloadFrom: endpoint) { people in
    List {
        ForEach(people) { person in
            Text("\(person.name) \(person.age)")
        }
    }
}
```

## Data Uploader

For the other more operational endpoint types, a `DataUploader` can be used to query the REST APIs in an easy way. 

First create a struct that conforms to the `DataUploader` protocol. In the following example, we'll use the `PublicUpload` kind (`POST` without authentication):

```swift
struct SimpleModelUploader: DataUploader {
    // Add anything to upload as properties here (must conform to Codable)
    var name: String
    var age: Int
    var tag: Bool
    
    // Endpoint for uploader (required)
    // Ensure the endpoint kinds is setup to encode Self
    var endpoint: Endpoint<EndpointKinds.PublicUpload<Self>, SimpleModel> {
        let url = URL(string: "http://127.0.0.1:8080/model")!
        return Endpoint(url: url)
    }
}
```

The protocol will automatically synthesize an `upload()` function based on the generic type of the `Endpoint` provided.

```swift
let uploader = SimpleModelUploader(name: "Tom", age: 20, tag: true)
let result = try await uploader.upload()
// result: Uploaded SimpleModel returned from the REST API
```

If the uploader needs additional data (such as authentication token), the synthesized function will require the parameter:

```swift
// Endpoint kind is EndpointKinds.Upload<Self>
let bearerToken = "abcde"
let result = try await uploader.upload(with: bearerToken)
```

This library is also very customizable. More documentations on the customizability will be coming soon...

## Contributions

Any contributions to the library are welcome! Please feel free to open a Pull Request or leave an issue.
