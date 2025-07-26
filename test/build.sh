#!/bin/bash

# Make sure we're in the test directory
cd "$(dirname "$0")"

# Install mops dependencies in the parent directory (where mops.toml is)
cd ..
mops i
cd test

# Ensure the build directory exists
mkdir -p ./build

echo "Building RQQ test canisters..."

# Function to build a single test file
build_test_file() {
    local file="$1"
    local base_name=$(basename "$file" .test.mo)
    
    echo "Processing $base_name..."
    
    # Run moc to produce the wasm file
    `dfx cache show`/moc `mops sources` --idl --hide-warnings --error-detail 0 -o "./build/${base_name}.wasm" --idl "$file" &&
    
    # Generate JavaScript bindings
    didc bind "./build/${base_name}.did" --target js > "./build/${base_name}.idl.js" &&
    
    # Generate TypeScript bindings
    didc bind "./build/${base_name}.did" --target ts > "./build/${base_name}.idl.d.ts"
    
    echo "Finished processing $base_name"
}

# Build all .test.mo files
for file in *.test.mo; do
    if [ -f "$file" ]; then
        build_test_file "$file"
    fi
done

echo "Build complete!" 