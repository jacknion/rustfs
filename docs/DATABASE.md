# Database Integration Guide

## Overview

RustFS supports optional PostgreSQL database integration for metadata storage and custom data operations. The database connection is **optional** and will only be initialized if configured.

## Configuration

### Environment Variables

```bash
# PostgreSQL connection URL
export RUSTFS_DATABASE_URL="postgres://username:password@localhost:5432/rustfs"

# Maximum number of connections in the pool (default: 10)
export RUSTFS_DATABASE_MAX_CONNECTIONS=10
```

### Command Line Arguments

```bash
rustfs \
  --database-url "postgres://username:password@localhost:5432/rustfs" \
  --database-max-connections 10 \
  --volumes /data1 /data2
```

## Database Connection Pool

The database connection pool is managed globally and initialized during server startup if a database URL is configured.

### Features

- **Automatic connection management**: Connection pool is created and managed automatically
- **Connection testing**: Health checks ensure connections are valid
- **Graceful shutdown**: Connection pool is properly closed during server shutdown
- **Security**: Database credentials are masked in logs

### Connection Configuration

| Parameter | Environment Variable | Default | Description |
|-----------|---------------------|---------|-------------|
| Database URL | `RUSTFS_DATABASE_URL` | None | PostgreSQL connection string |
| Max Connections | `RUSTFS_DATABASE_MAX_CONNECTIONS` | 10 | Maximum pool size |
| Connect Timeout | - | 30s | Connection timeout |
| Idle Timeout | - | 600s | Idle connection timeout |

## API Endpoints

### Database Health Check

```bash
GET /rustfs/admin/v3/database/health
```

**Response:**

```json
{
  "status": "ok",
  "connected": true,
  "message": "Database connection is healthy",
  "timestamp": "2025-11-13T10:00:00Z"
}
```

### Database Example Query

```bash
GET /rustfs/admin/v3/database/example
```

**Response:**

```json
{
  "status": "success",
  "currentTime": "2025-11-13 10:00:00.123456+00",
  "databaseVersion": "PostgreSQL 16.0 on x86_64-pc-linux-gnu",
  "message": "Database query executed successfully"
}
```

## Usage in Custom Handlers

### Getting the Database Pool

```rust
use crate::storage::database::get_database_pool;

// Get the global database pool
let pool = get_database_pool()
    .ok_or_else(|| s3_error!(InternalError, "Database not initialized"))?;
```

### Example Query

```rust
use sqlx::Row;

// Execute a query
let result: (String,) = sqlx::query_as("SELECT NOW()::TEXT")
    .fetch_one(pool)
    .await
    .map_err(|e| s3_error!(InternalError, format!("Query failed: {e}")))?;

println!("Current time: {}", result.0);
```

### Example with Parameters

```rust
// Query with parameters
let bucket_name = "my-bucket";
let result = sqlx::query!(
    "SELECT * FROM buckets WHERE name = $1",
    bucket_name
)
.fetch_one(pool)
.await?;
```

## Database Schema

You can create your own database schema for custom metadata storage. Here's an example:

```sql
-- Create a table for custom metadata
CREATE TABLE IF NOT EXISTS custom_metadata (
    id SERIAL PRIMARY KEY,
    bucket_name VARCHAR(255) NOT NULL,
    object_key VARCHAR(1024) NOT NULL,
    metadata_key VARCHAR(255) NOT NULL,
    metadata_value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(bucket_name, object_key, metadata_key)
);

-- Create indexes
CREATE INDEX idx_bucket_name ON custom_metadata(bucket_name);
CREATE INDEX idx_object_key ON custom_metadata(object_key);
```

## Running RustFS with Database

### Using Docker Compose

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: rustfs
      POSTGRES_PASSWORD: rustfs_password
      POSTGRES_DB: rustfs
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  rustfs:
    image: rustfs/rustfs:latest
    environment:
      RUSTFS_DATABASE_URL: "postgres://rustfs:rustfs_password@postgres:5432/rustfs"
      RUSTFS_DATABASE_MAX_CONNECTIONS: "20"
      RUSTFS_VOLUMES: "/data"
    ports:
      - "9000:9000"
    volumes:
      - rustfs_data:/data
    depends_on:
      - postgres

volumes:
  postgres_data:
  rustfs_data:
```

### Using Local PostgreSQL

```bash
# Start PostgreSQL
docker run -d \
  --name rustfs-postgres \
  -e POSTGRES_USER=rustfs \
  -e POSTGRES_PASSWORD=rustfs_password \
  -e POSTGRES_DB=rustfs \
  -p 5432:5432 \
  postgres:16

# Run RustFS with database
rustfs \
  --database-url "postgres://rustfs:rustfs_password@localhost:5432/rustfs" \
  --database-max-connections 20 \
  --volumes /data
```

## Testing Database Connection

### Using curl

```bash
# Check database health
curl http://localhost:9000/rustfs/admin/v3/database/health

# Run example query
curl http://localhost:9000/rustfs/admin/v3/database/example
```

### Expected Output

```json
{
  "status": "ok",
  "connected": true,
  "message": "Database connection is healthy",
  "timestamp": "2025-11-13T10:00:00Z"
}
```

## Error Handling

### Database Not Configured

If database URL is not provided, the database endpoints will return:

```json
{
  "status": "error",
  "connected": false,
  "message": "Database not configured or initialized",
  "timestamp": "2025-11-13T10:00:00Z"
}
```

### Connection Failed

If database connection fails during startup:

```
ERROR Failed to initialize database connection pool: connection refused
```

The server will **fail to start** if a database URL is configured but connection fails.

## Best Practices

1. **Connection Pooling**: Use the global pool instead of creating new connections
2. **Error Handling**: Always handle database errors gracefully
3. **Prepared Statements**: Use parameterized queries to prevent SQL injection
4. **Transactions**: Use transactions for multi-statement operations
5. **Monitoring**: Regularly check database health endpoint
6. **Security**: Never log database credentials in plain text

## Troubleshooting

### Connection Timeout

```bash
# Increase connection timeout by modifying the code
# Default is 30 seconds in database.rs
```

### Too Many Connections

```bash
# Reduce max connections
export RUSTFS_DATABASE_MAX_CONNECTIONS=5
```

### SSL/TLS Required

```bash
# Add SSL mode to connection string
export RUSTFS_DATABASE_URL="postgres://user:pass@host/db?sslmode=require"
```

## Migration Support

RustFS includes SQLx migration support. You can create migrations in your project:

```bash
# Create a migration
sqlx migrate add create_custom_metadata

# Edit the migration file
# migrations/XXXXXX_create_custom_metadata.sql

# Migrations are automatically applied on startup (if configured)
```

## Performance Considerations

- **Pool Size**: Adjust based on workload (default: 10)
- **Connection Reuse**: Pool automatically reuses connections
- **Query Optimization**: Use indexes and optimize queries
- **Monitoring**: Track slow queries and connection pool metrics

## Security

- **Credentials**: Store database credentials securely
- **Network**: Use SSL/TLS for database connections
- **Access Control**: Limit database user permissions
- **Logging**: Database URLs are automatically masked in logs
