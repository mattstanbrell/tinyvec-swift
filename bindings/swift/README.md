# TinyVec Swift Bindings

Swift bindings for TinyVec, a lightweight vector database optimized for mobile devices.

## Features

- Efficient vector similarity search
- Metadata filtering
- Low memory footprint
- Designed for iOS environments
- Async/await support for non-blocking operations

## Requirements

- iOS 13.0+ / macOS 10.15+
- Swift 5.3+
- Xcode 12.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/tylerpuig/tinyvec.git", from: "0.2.0")
]
```

Then add the dependency to your target:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "TinyVec", package: "tinyvec")
        ]
    )
]
```

## Quick Start

```swift
import TinyVec

// Initialize client
let config = TinyVecConnectionConfig(dimensions: 128)
let client = try TinyVecClient(
    filePath: "/path/to/your/vectordb.db", 
    config: config
)

// Insert vectors
let vectors = [
    TinyVecInsertion(
        vector: [0.1, 0.2, ...], // 128 dimensions
        metadata: ["category": "article", "title": "Example"]
    )
]
try await client.insert(data: vectors)

// Search for similar vectors
let results = try await client.search(
    query: [0.1, 0.2, ...], // 128 dimensions
    topK: 10
)

// Search with filter
let filteredResults = try await client.search(
    query: [0.1, 0.2, ...],
    topK: 10,
    filter: TinyVecFilterOptions(filter: "metadata.category = 'article'")
)

// Delete vectors
try await client.deleteByIds(ids: [1, 2, 3])
try await client.deleteByFilter(
    options: TinyVecFilterOptions(filter: "metadata.archived = true")
)
```

## Documentation

For detailed documentation, see the [TinyVec Documentation](https://github.com/tylerpuig/tinyvec).

## Demo Application

The package includes a demo application that demonstrates the core functionality:

```bash
swift run TinyVecDemo
```

## License

TinyVec is available under the MIT license. See the LICENSE file for more info.