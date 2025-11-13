#!/bin/bash
# RustFS with PostgreSQL Database Integration Example
# This script demonstrates how to run RustFS with PostgreSQL database support

# PostgreSQL Connection Configuration
export RUSTFS_DATABASE_URL="postgres://rustfs_user:rustfs_password@localhost:5432/rustfs_db"
export RUSTFS_DATABASE_MAX_CONNECTIONS=20

# RustFS Basic Configuration
export RUSTFS_VOLUMES="/data1 /data2"
export RUSTFS_ADDRESS="0.0.0.0:9000"
export RUSTFS_ACCESS_KEY="rustfsadmin"
export RUSTFS_SECRET_KEY="rustfsadmin"
export RUSTFS_CONSOLE_ENABLE=true
export RUSTFS_CONSOLE_ADDRESS="0.0.0.0:9001"

# Optional: Observability Configuration
# export RUSTFS_OBS_ENDPOINT="http://localhost:4317"

# Start RustFS
echo "Starting RustFS with PostgreSQL database integration..."
echo "Database URL: $RUSTFS_DATABASE_URL"
echo "Max Connections: $RUSTFS_DATABASE_MAX_CONNECTIONS"
echo ""

# Run RustFS
./target/release/rustfs \
  --database-url "$RUSTFS_DATABASE_URL" \
  --database-max-connections "$RUSTFS_DATABASE_MAX_CONNECTIONS" \
  --volumes $RUSTFS_VOLUMES \
  --address "$RUSTFS_ADDRESS" \
  --access-key "$RUSTFS_ACCESS_KEY" \
  --secret-key "$RUSTFS_SECRET_KEY" \
  --console-enable \
  --console-address "$RUSTFS_CONSOLE_ADDRESS"
