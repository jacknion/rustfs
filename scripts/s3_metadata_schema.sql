-- =====================================================
-- RustFS S3 对象元数据数据库表结构
-- 数据库：PostgreSQL 16+
-- 设计模式：单表扁平化（适合中小规模 < 1 亿对象）
-- =====================================================

-- 删除已存在的表（谨慎使用！）
-- DROP TABLE IF EXISTS s3_objects CASCADE;
-- DROP TABLE IF EXISTS bucket_stats CASCADE;
-- DROP TABLE IF EXISTS tag_statistics CASCADE;

-- =====================================================
-- 主表：S3 对象元数据
-- =====================================================
CREATE TABLE IF NOT EXISTS s3_objects (
    -- 主键
    id BIGSERIAL PRIMARY KEY,
    
    -- ==================== S3 基本信息 ====================
    bucket TEXT NOT NULL,
    object_key TEXT NOT NULL,  -- 避免与 SQL 保留字 'key' 冲突
    size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
    last_modified TIMESTAMPTZ NOT NULL,
    etag TEXT NOT NULL,
    content_type TEXT,
    
    -- ==================== 存储相关 ====================
    storage_class VARCHAR(20) DEFAULT 'STANDARD' 
        CHECK (storage_class IN ('STANDARD', 'REDUCED_REDUNDANCY', 'GLACIER', 'GLACIER_IR', 'DEEP_ARCHIVE', 'INTELLIGENT_TIERING', 'ONEZONE_IA', 'STANDARD_IA')),
    version_id TEXT,  -- 版本控制支持
    is_delete_marker BOOLEAN DEFAULT false,
    is_latest BOOLEAN DEFAULT true,  -- 是否为最新版本
    
    -- ==================== 核心：标签存储（JSONB 格式）====================
    -- 示例：{"Project": "analytics", "Environment": "prod", "Owner": "alice"}
    tags JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- ==================== 用户自定义元数据（x-amz-meta-*）====================
    -- 示例：{"x-amz-meta-custom-field": "value", "x-amz-meta-category": "documents"}
    user_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- ==================== 安全与合规 ====================
    is_encrypted BOOLEAN DEFAULT false,
    encryption_algorithm VARCHAR(50),  -- 如：AES256, aws:kms
    kms_key_id TEXT,  -- KMS Key ID
    
    -- 对象锁定（Object Lock）
    retention_mode VARCHAR(20) CHECK (retention_mode IN ('GOVERNANCE', 'COMPLIANCE', NULL)),
    retention_until TIMESTAMPTZ,
    legal_hold BOOLEAN DEFAULT false,
    
    -- ==================== 访问控制 ====================
    owner_id TEXT,  -- 对象所有者
    acl_grants JSONB,  -- ACL 权限列表（可选）
    
    -- ==================== 性能优化字段 ====================
    access_count BIGINT DEFAULT 0,  -- 访问次数（可选，用于热点分析）
    last_accessed TIMESTAMPTZ,  -- 最后访问时间
    
    -- ==================== 元数据 ====================
    checksum_crc32 TEXT,  -- CRC32 校验和
    checksum_sha256 TEXT,  -- SHA256 校验和
    multipart_upload_id TEXT,  -- 分段上传 ID
    
    -- ==================== 时间戳 ====================
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- ==================== 约束 ====================
    -- 唯一约束：同一个 bucket 和 key 只能有一条记录（忽略版本）
    CONSTRAINT unique_bucket_key UNIQUE (bucket, object_key)
);

-- =====================================================
-- 索引设计（性能优化）
-- =====================================================

-- 1. 必需索引：快速定位对象
CREATE INDEX IF NOT EXISTS idx_bucket_key 
    ON s3_objects (bucket, object_key);

-- 2. GIN 索引：加速 JSONB 标签查询（核心）
CREATE INDEX IF NOT EXISTS idx_tags_gin 
    ON s3_objects USING GIN (tags);

-- 3. GIN 索引：用户元数据查询
CREATE INDEX IF NOT EXISTS idx_user_metadata_gin 
    ON s3_objects USING GIN (user_metadata);

-- 4. 时间范围查询
CREATE INDEX IF NOT EXISTS idx_last_modified 
    ON s3_objects (last_modified DESC);

CREATE INDEX IF NOT EXISTS idx_created_at 
    ON s3_objects (created_at DESC);

-- 5. 存储类型查询
CREATE INDEX IF NOT EXISTS idx_bucket_storage_class 
    ON s3_objects (bucket, storage_class);

-- 6. 合规查询（带条件索引，节省空间）
CREATE INDEX IF NOT EXISTS idx_retention 
    ON s3_objects (retention_until) 
    WHERE retention_until IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_legal_hold 
    ON s3_objects (bucket, object_key) 
    WHERE legal_hold = true;

-- 7. 加密对象查询
CREATE INDEX IF NOT EXISTS idx_encrypted 
    ON s3_objects (bucket) 
    WHERE is_encrypted = true;

-- 8. 版本控制（如果启用）
CREATE INDEX IF NOT EXISTS idx_version 
    ON s3_objects (bucket, object_key, version_id) 
    WHERE version_id IS NOT NULL;

-- 9. 大小范围查询
CREATE INDEX IF NOT EXISTS idx_size_bytes 
    ON s3_objects (size_bytes) 
    WHERE size_bytes > 1073741824;  -- > 1GB

-- 10. ETag 查询（去重）
CREATE INDEX IF NOT EXISTS idx_etag 
    ON s3_objects (etag);

-- =====================================================
-- 触发器：自动更新 updated_at 字段
-- =====================================================
CREATE OR REPLACE FUNCTION update_s3_objects_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER s3_objects_updated_at_trigger
    BEFORE UPDATE ON s3_objects
    FOR EACH ROW
    EXECUTE FUNCTION update_s3_objects_updated_at();

-- =====================================================
-- 辅助表：Bucket 统计信息（缓存表）
-- =====================================================
CREATE TABLE IF NOT EXISTS bucket_stats (
    bucket TEXT PRIMARY KEY,
    object_count BIGINT DEFAULT 0 CHECK (object_count >= 0),
    total_size_bytes BIGINT DEFAULT 0 CHECK (total_size_bytes >= 0),
    largest_object_size BIGINT DEFAULT 0,
    smallest_object_size BIGINT,
    avg_object_size BIGINT,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 触发器：更新 bucket 统计信息（可选，性能影响需评估）
CREATE OR REPLACE FUNCTION update_bucket_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO bucket_stats (bucket, object_count, total_size_bytes)
        VALUES (NEW.bucket, 1, NEW.size_bytes)
        ON CONFLICT (bucket) DO UPDATE SET
            object_count = bucket_stats.object_count + 1,
            total_size_bytes = bucket_stats.total_size_bytes + NEW.size_bytes,
            last_updated = NOW();
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE bucket_stats SET
            object_count = GREATEST(0, object_count - 1),
            total_size_bytes = GREATEST(0, total_size_bytes - OLD.size_bytes),
            last_updated = NOW()
        WHERE bucket = OLD.bucket;
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE bucket_stats SET
            total_size_bytes = total_size_bytes - OLD.size_bytes + NEW.size_bytes,
            last_updated = NOW()
        WHERE bucket = NEW.bucket;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 注意：此触发器可能影响写入性能，建议改用定期批量更新
-- CREATE TRIGGER bucket_stats_trigger
--     AFTER INSERT OR UPDATE OR DELETE ON s3_objects
--     FOR EACH ROW
--     EXECUTE FUNCTION update_bucket_stats();

-- =====================================================
-- 辅助表：标签使用统计
-- =====================================================
CREATE TABLE IF NOT EXISTS tag_statistics (
    tag_key TEXT PRIMARY KEY,
    usage_count BIGINT DEFAULT 0 CHECK (usage_count >= 0),
    distinct_values_count INT DEFAULT 0,
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_tag_usage 
    ON tag_statistics (usage_count DESC);

-- =====================================================
-- 视图：常用查询优化
-- =====================================================

-- 视图 1：最新对象（按 bucket）
CREATE OR REPLACE VIEW recent_objects AS
SELECT 
    bucket,
    object_key,
    size_bytes,
    last_modified,
    storage_class,
    tags
FROM s3_objects
WHERE last_modified > NOW() - INTERVAL '7 days'
ORDER BY last_modified DESC;

-- 视图 2：大文件对象（> 100MB）
CREATE OR REPLACE VIEW large_objects AS
SELECT 
    bucket,
    object_key,
    size_bytes,
    size_bytes / 1024.0 / 1024.0 AS size_mb,
    storage_class,
    last_modified
FROM s3_objects
WHERE size_bytes > 104857600  -- 100MB
ORDER BY size_bytes DESC;

-- 视图 3：加密对象统计
CREATE OR REPLACE VIEW encrypted_objects_summary AS
SELECT 
    bucket,
    COUNT(*) AS encrypted_count,
    SUM(size_bytes) AS total_encrypted_bytes,
    encryption_algorithm
FROM s3_objects
WHERE is_encrypted = true
GROUP BY bucket, encryption_algorithm;

-- =====================================================
-- 示例数据（测试用）
-- =====================================================
INSERT INTO s3_objects (bucket, object_key, size_bytes, last_modified, etag, content_type, tags, user_metadata)
VALUES 
    (
        'example-bucket', 
        'documents/report-2025.pdf', 
        2048576, 
        NOW(), 
        'abc123def456', 
        'application/pdf',
        '{"Project": "analytics", "Environment": "prod", "Owner": "alice", "Confidential": "true"}'::jsonb,
        '{"x-amz-meta-category": "financial", "x-amz-meta-department": "accounting"}'::jsonb
    ),
    (
        'example-bucket', 
        'images/logo.png', 
        51200, 
        NOW() - INTERVAL '1 day', 
        'png789hash', 
        'image/png',
        '{"Project": "website", "Environment": "prod", "Public": "true"}'::jsonb,
        '{}'::jsonb
    ),
    (
        'backup-bucket', 
        'db-backup-20251113.tar.gz', 
        1073741824, 
        NOW() - INTERVAL '3 hours', 
        'backup456', 
        'application/gzip',
        '{"Type": "backup", "Retention": "90days", "Critical": "true"}'::jsonb,
        '{"x-amz-meta-backup-type": "full", "x-amz-meta-source-db": "postgres-prod"}'::jsonb
    )
ON CONFLICT (bucket, object_key) DO NOTHING;

-- 更新 bucket 统计信息
INSERT INTO bucket_stats (bucket, object_count, total_size_bytes)
SELECT 
    bucket,
    COUNT(*),
    SUM(size_bytes)
FROM s3_objects
GROUP BY bucket
ON CONFLICT (bucket) DO UPDATE SET
    object_count = EXCLUDED.object_count,
    total_size_bytes = EXCLUDED.total_size_bytes,
    last_updated = NOW();

-- =====================================================
-- 查询示例（验证功能）
-- =====================================================

-- 示例 1：查找特定标签的对象
-- SELECT bucket, object_key, tags 
-- FROM s3_objects
-- WHERE tags @> '{"Project": "analytics", "Environment": "prod"}'::jsonb;

-- 示例 2：查找包含某个标签键的对象
-- SELECT bucket, object_key, tags->>'Project' AS project
-- FROM s3_objects
-- WHERE tags ? 'Project';

-- 示例 3：模糊匹配标签值
-- SELECT bucket, object_key, tags
-- FROM s3_objects
-- WHERE tags->>'Owner' LIKE '%alice%';

-- 示例 4：查找最近 7 天的对象
-- SELECT bucket, object_key, last_modified
-- FROM s3_objects
-- WHERE last_modified > NOW() - INTERVAL '7 days'
-- ORDER BY last_modified DESC;

-- 示例 5：按 bucket 统计对象数和总大小
-- SELECT 
--     bucket,
--     COUNT(*) AS object_count,
--     SUM(size_bytes) AS total_bytes,
--     SUM(size_bytes) / 1024.0 / 1024.0 / 1024.0 AS total_gb,
--     AVG(size_bytes) AS avg_size
-- FROM s3_objects
-- GROUP BY bucket;

-- 示例 6：查找大于 1GB 的对象
-- SELECT bucket, object_key, size_bytes / 1024.0 / 1024.0 / 1024.0 AS size_gb
-- FROM s3_objects
-- WHERE size_bytes > 1073741824
-- ORDER BY size_bytes DESC;

-- 示例 7：查找加密对象
-- SELECT bucket, object_key, encryption_algorithm
-- FROM s3_objects
-- WHERE is_encrypted = true;

-- 示例 8：查找有法定保留的对象
-- SELECT bucket, object_key, retention_until, legal_hold
-- FROM s3_objects
-- WHERE legal_hold = true OR retention_until > NOW();

-- =====================================================
-- 性能分析
-- =====================================================

-- 分析表统计信息
-- ANALYZE s3_objects;

-- 查看查询执行计划
-- EXPLAIN (ANALYZE, BUFFERS) 
-- SELECT * FROM s3_objects 
-- WHERE tags @> '{"Project": "analytics"}'::jsonb;

-- 查看索引使用情况
-- SELECT 
--     schemaname,
--     tablename,
--     indexname,
--     idx_scan,
--     idx_tup_read,
--     idx_tup_fetch
-- FROM pg_stat_user_indexes
-- WHERE tablename = 's3_objects'
-- ORDER BY idx_scan DESC;

-- =====================================================
-- 维护任务
-- =====================================================

-- 定期更新统计信息（建议每天运行）
-- ANALYZE s3_objects;

-- 重建索引（如果性能下降）
-- REINDEX TABLE s3_objects;

-- 清理过期的删除标记（如果启用版本控制）
-- DELETE FROM s3_objects 
-- WHERE is_delete_marker = true 
--   AND created_at < NOW() - INTERVAL '90 days';

-- =====================================================
-- 权限设置
-- =====================================================

-- 授予应用用户权限
GRANT SELECT, INSERT, UPDATE, DELETE ON s3_objects TO rustfs_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON bucket_stats TO rustfs_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON tag_statistics TO rustfs_user;
GRANT USAGE, SELECT ON SEQUENCE s3_objects_id_seq TO rustfs_user;

-- 只读用户（用于分析查询）
-- CREATE USER rustfs_readonly WITH PASSWORD 'readonly_password';
-- GRANT CONNECT ON DATABASE rustfs_db TO rustfs_readonly;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO rustfs_readonly;

-- =====================================================
-- 完成提示
-- =====================================================
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RustFS S3 元数据数据库初始化完成！';
    RAISE NOTICE '========================================';
    RAISE NOTICE '已创建表：';
    RAISE NOTICE '  - s3_objects (主表)';
    RAISE NOTICE '  - bucket_stats (统计表)';
    RAISE NOTICE '  - tag_statistics (标签统计)';
    RAISE NOTICE '';
    RAISE NOTICE '已创建索引：10 个（包括 GIN 索引）';
    RAISE NOTICE '已创建视图：3 个';
    RAISE NOTICE '已创建触发器：1 个';
    RAISE NOTICE '';
    RAISE NOTICE '下一步：';
    RAISE NOTICE '1. 运行查询示例验证功能';
    RAISE NOTICE '2. 配置 RustFS 连接数据库';
    RAISE NOTICE '3. 启动元数据同步服务';
    RAISE NOTICE '========================================';
END $$;
