-- RustFS Database Initialization Script
-- This script creates the initial database schema for RustFS metadata storage

-- Create custom metadata table
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

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_custom_metadata_bucket_name ON custom_metadata(bucket_name);
CREATE INDEX IF NOT EXISTS idx_custom_metadata_object_key ON custom_metadata(object_key);
CREATE INDEX IF NOT EXISTS idx_custom_metadata_created_at ON custom_metadata(created_at);

-- Create audit log table (example)
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    user_id VARCHAR(255),
    bucket_name VARCHAR(255),
    object_key VARCHAR(1024),
    action VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    request_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for audit logs
CREATE INDEX IF NOT EXISTS idx_audit_logs_event_type ON audit_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_bucket_name ON audit_logs(bucket_name);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);

-- Create bucket statistics table (example)
CREATE TABLE IF NOT EXISTS bucket_statistics (
    id SERIAL PRIMARY KEY,
    bucket_name VARCHAR(255) NOT NULL UNIQUE,
    object_count BIGINT DEFAULT 0,
    total_size_bytes BIGINT DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for bucket statistics
CREATE INDEX IF NOT EXISTS idx_bucket_statistics_bucket_name ON bucket_statistics(bucket_name);
CREATE INDEX IF NOT EXISTS idx_bucket_statistics_last_updated ON bucket_statistics(last_updated);

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for custom_metadata table
CREATE TRIGGER update_custom_metadata_updated_at
    BEFORE UPDATE ON custom_metadata
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create trigger for bucket_statistics table
CREATE TRIGGER update_bucket_statistics_updated_at
    BEFORE UPDATE ON bucket_statistics
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert some example data
INSERT INTO custom_metadata (bucket_name, object_key, metadata_key, metadata_value)
VALUES 
    ('example-bucket', 'test-object.txt', 'custom-tag', 'production'),
    ('example-bucket', 'test-object.txt', 'owner', 'admin')
ON CONFLICT (bucket_name, object_key, metadata_key) DO NOTHING;

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rustfs_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rustfs_user;

-- Display confirmation message
DO $$
BEGIN
    RAISE NOTICE 'RustFS database initialized successfully!';
    RAISE NOTICE 'Tables created: custom_metadata, audit_logs, bucket_statistics';
END $$;
