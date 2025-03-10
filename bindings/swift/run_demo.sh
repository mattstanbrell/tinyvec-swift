#!/bin/bash

# Set error handling
set -e

echo "Building and running TinyVec Swift Demo..."

# Navigate to the Swift bindings directory
cd "$(dirname "$0")"

# Build the Swift package
swift build

# Run the demo
swift run TinyVecDemo