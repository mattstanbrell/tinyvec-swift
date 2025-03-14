# TinyVec Swift Bindings

Swift bindings for TinyVec, a lightweight vector database optimized for mobile devices.

## Installation

### Using TinyVec Locally in Xcode

1. In Xcode, go to File > Add Packages Depenedencies...
3. Click "Add Local..."
4. Navigate to the `bindings/swift/src` directory
5. Click "Add Package"

## Quick Start

```swift
import TinyVec

// Initialize client with vector dimension
let config = TinyVecConnectionConfig(dimensions: 512)
let client = try TinyVecClient(
    filePath: "path/to/vectors.db",
    config: config
)

// Insert vectors with metadata
let vectors = [
    TinyVecInsertion(
        vector: [0.1, 0.2, ...], // 512 dimensions
        metadata: ["id": "doc1", "title": "Example", "text": "Sample text"]
    )
]
try await client.insert(data: vectors)

// Search for similar vectors
let results = try await client.search(
    query: [0.1, 0.2, ...], // 512 dimensions
    topK: 10
)

// Process search results
for result in results {
    print("ID: \(result.id)")
    print("Similarity: \(result.similarity)")
    print("Metadata: \(result.metadata)")
}
```

## Demos

### Running the Demo Test Script

To run the included demo application:

1. Navigate to the Swift bindings directory:
```bash
cd bindings/swift
```

2. Run the demo script:
```bash
./run_demo.sh
```

This will build and run a demo that showcases TinyVec's core functionality by:
- Creating a temporary vector database
- Inserting sample 4-dimensional vectors with metadata
- Performing similarity searches to demonstrate vector matching
- Cleaning up the test database when done

### Testing with TinyVecTest App

You can explore TinyVec's functionality using our interactive test application:

1. Open the TinyVecTest.xcodeproj in the `bindings/swift/TinyVecTest` directory
2. Build and run the project

Launching the app will insert 100,000 512 dimension vectors. 20 of these are embeddings of real text, the rest are random.
You can then search the embeddings.

## Documentation

For detailed documentation, see the [TinyVec Documentation](https://github.com/tylerpuig/tinyvec).
