# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ATLogin is an OIDC (OpenID Connect) Identity Provider that uses ATProto OAuth for authentication. Users authenticate using their ATProto handle (Bluesky accounts) which initiates an OAuth flow with their PDS (Personal Data Server). The provider accepts any domain and returns the full email as provided.

## Key Architecture

### Authentication Flow
1. **OIDC Client** requests authentication with `login_hint` parameter (format: `user@domain`)
2. **ATLogin** parses the login hint to extract ATProto handle and webfinger domain using special rules:
   - Default: `user@domain` → `@user.domain` (ATProto handle), `domain` (webfinger domain)
   - If "user." is a prefix of domain: `user@user.example.com` → `@user.example.com`, `user.example.com`
   - Special case for backward compat: `user@at.apenwarr.ca` → `@user`, `at.apenwarr.ca`
3. **ATProto OAuth** flow is initiated using the Bluesky Indigo library
4. User authenticates with their PDS
5. ATLogin receives callback, verifies handle ownership via DID resolution
6. OIDC authorization code is issued to the original client
7. Client exchanges code for tokens containing user info (DID, handle, email)

### Code Structure

**cmd/atlogin/main.go** - Main OIDC IdP server
- `idpServer` struct manages OIDC endpoints and ATProto OAuth clients
- Dynamic issuer URL detection: uses `Host` header if not configured, allowing domain-independent deployment
- OAuth client instances are cached per issuer URL (`oauthClients` map)
- `customAuthStore` implements `oauth.ClientAuthStore` and links ATProto state to OIDC sessions
- Key endpoints: `/authorize`, `/token`, `/userinfo`, `/atproto/callback`, `/.well-known/openid-configuration`, `/.well-known/webfinger`
- Security: Verifies authenticated DID matches requested handle via `resolveHandleToDID()`

**testapp/testapp.go** - Embedded test application
- Can run standalone (via cmd/apptest) or embedded in main server
- Provides domain verification tool at `/verify` to check DNS, HTTPS, WebFinger setup
- Provides login test flow demonstrating the full OIDC integration
- Uses dynamic issuer detection like main server

**Configuration** (state/config.json)
- `addr`: Listen address (default: ":9411")
- `issuer`: OIDC issuer URL (optional, dynamically determined from Host header if unset)
- `client_name`: Friendly name for Bluesky auth page (default: "ATLogin")
- `secrets`: Map of OIDC client IDs to client secrets

**State Directory** (default: ./state)
- `config.json`: Server configuration with client credentials
- `signing-key.json`: RSA key for signing JWTs
- Environment variables: `ATLOGIN_CONFIG`, `ATLOGIN_SIGNING_KEY` (base64-encoded) override files

### Login Hint Parsing Rules

The `parseLoginHint()` function (duplicated in main.go and testapp.go) implements crucial logic:
- Parses `user@domain` format
- Determines ATProto handle based on pattern matching
- See parse_test.go for comprehensive test cases

## Development Commands

### Quick Start

Initialize the development environment with a test client:
```bash
./init-dev.sh
# Outputs client ID and secret, then run:
./atlogin -state-dir=./state
```

### Build
```bash
go build -v -o atlogin ./cmd/atlogin
go build -v -o apptest ./cmd/apptest
```

### Run Tests
```bash
# Run all tests
go test ./...

# Run specific test file
go test ./cmd/atlogin/parse_test.go ./cmd/atlogin/main.go
```

### Initialize State Directory
```bash
# Create state directory with signing key
./atlogin -state-dir=./state -init

# Add a new OIDC client
./atlogin -state-dir=./state -new-client <client-id>
# Outputs the generated client secret to stdout
```

### Run Server
```bash
# Main server (includes embedded test app)
./atlogin -state-dir=./state

# Standalone test app
./apptest -client-id=<id> -client-secret=<secret> -issuer=https://at.example.com
```

### Docker

Build and run with Docker:
```bash
docker build -t atlogin .
docker run -p 9411:9411 -v ./state:/app/state atlogin
```

### Docker Compose

Run with Docker Compose:
```bash
# Initialize state directory with a test client
mkdir -p state
cat > state/config.json << 'EOF'
{
  "addr": ":9411",
  "client_name": "ATLogin",
  "secrets": {
    "test-client": "test-secret-12345"
  }
}
EOF

# Start the atlogin service
docker compose up -d

# Start with test app (optional)
docker compose --profile test up -d
```

The Docker Compose setup includes:
- `atlogin` service on port 9411 with healthcheck
- `apptest` service on port 8080 (test profile only)
- Volume mount for state directory
- Support for environment variable configuration

## Important Implementation Details

### Dynamic Issuer Support
The code is designed to work regardless of what domain it's hosted on. If `issuer` is not set in config, the server dynamically constructs issuer URLs from the `Host` header and `X-Forwarded-Proto`/TLS detection. This means:
- Each request can potentially use a different issuer URL
- OAuth clients are cached per issuer URL in `oauthClients` map
- Test app also supports dynamic issuer detection

### Security Verification
In `serveATProtoCallback()`, the server MUST verify that the authenticated DID matches the handle that was used to initiate the flow. This is done via:
1. Get the ATProto state from the callback
2. Look up the original OIDC session with the requested handle
3. Resolve the handle to DID via `resolveHandleToDID()` using Bluesky's public API
4. Compare authenticated DID with resolved DID
5. Return 403 if mismatch

### Email Construction
The user's email in the final OIDC response is constructed as `handle@domain` where domain is the original webfinger domain from the login_hint, preserving the user's intended login identity.

### WebFinger Endpoint
The server provides two WebFinger endpoints:
- `/.well-known/webfinger` - Standard location
- `/helpers/webfinger` - Stable endpoint for reverse proxying from other domains

This allows reverse proxy configuration like:
```nginx
location /.well-known/webfinger {
    proxy_pass https://atlogin.example.com/helpers/webfinger;
    proxy_set_header Host $host;
}
```

## Continuous Integration

The `.github/workflows/test.yml` workflow runs on every push and pull request:

1. **Test Job**: Runs `go test ./...` and builds both binaries
2. **Docker Job**:
   - Builds Docker images using docker-compose
   - Initializes state directory with test client
   - Starts services and validates endpoints
   - Tests OIDC discovery, JWKS, and WebFinger endpoints

To run the same tests locally:
```bash
# Run Go tests
go test ./...

# Run Docker tests
docker compose build
mkdir -p state
echo '{"addr":":9411","secrets":{"test-client":"test-secret-12345"}}' > state/config.json
docker compose up -d
curl http://localhost:9411/.well-known/openid-configuration
docker compose down
```

## Testing Notes

- The test app at `/verify` is valuable for debugging WebFinger/DNS setup issues
- `parse_test.go` contains comprehensive test cases for the login hint parsing logic
- When testing, use real ATProto accounts (Bluesky accounts) as the handle resolution requires working DIDs
