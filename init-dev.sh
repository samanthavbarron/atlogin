#!/bin/bash
# Helper script to initialize the development environment

set -e

STATE_DIR="${STATE_DIR:-./state}"
CLIENT_ID="${CLIENT_ID:-test-client}"

echo "Initializing ATLogin development environment..."

# Create state directory
mkdir -p "$STATE_DIR"

# Build the binary
echo "Building atlogin..."
go build -v -o atlogin ./cmd/atlogin

# Initialize state directory and signing key
echo "Initializing state directory..."
./atlogin -state-dir="$STATE_DIR" -init

# Add a test client
echo "Adding test client '$CLIENT_ID'..."
SECRET=$(./atlogin -state-dir="$STATE_DIR" -new-client "$CLIENT_ID")

echo ""
echo "✓ Development environment initialized!"
echo ""
echo "State directory: $STATE_DIR"
echo "Client ID: $CLIENT_ID"
echo "Client Secret: $SECRET"
echo ""
echo "To start the server:"
echo "  ./atlogin -state-dir=$STATE_DIR"
echo ""
echo "The server will listen on http://localhost:9411"
echo "Test app will be available at http://localhost:9411/"
