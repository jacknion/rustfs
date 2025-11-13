-- =====================================================
-- RustFS S3 元数据数据库索引验证脚本
-- 用途：验证生产环境是否已创建所有必要的索引
-- 使用方法：psql -U rustfs_user -d rustfs_db -f verify_indexes.sql
-- =====================================================

\echo '========================================='
\echo 'RustFS S3 Metadata Database Index Verification'
\echo '========================================='
\echo ''

-- =====================================================
-- 1. 检查表是否存在
-- =====================================================
\echo '1. Checking if s3_objects table exists...'
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_name = 's3_objects'
        ) 
        THEN '✓ Table s3_objects exists'
        ELSE '✗ ERROR: Table s3_objects not found!'
    END AS status;
\echo ''

-- =====================================================
-- 2. 检查必需索引
-- =====================================================
\echo '2. Checking required indexes...'
\echo ''

-- 创建临时表存储预期索引
CREATE TEMP TABLE IF NOT EXISTS expected_indexes (
    index_name TEXT PRIMARY KEY,
    index_type TEXT,
    description TEXT,
    priority TEXT
);

-- 插入预期的索引列表
INSERT INTO expected_indexes VALUES
    -- 高优先级索引（性能关键）
    ('idx_bucket_key', 'btree', 'Fast object lookup by bucket and key', 'HIGH'),
    ('idx_tags_gin', 'gin', 'Tag-based queries (core feature)', 'HIGH'),
    ('idx_last_modified', 'btree', 'Time-range queries', 'HIGH'),
    
    -- 中优先级索引（常用查询）
    ('idx_user_metadata_gin', 'gin', 'User metadata queries', 'MEDIUM'),
    ('idx_created_at', 'btree', 'Creation time queries', 'MEDIUM'),
    ('idx_bucket_storage_class', 'btree', 'Storage class filtering', 'MEDIUM'),
    ('idx_etag', 'btree', 'Deduplication queries', 'MEDIUM'),
    
    -- 低优先级索引（条件索引，节省空间）
    ('idx_retention', 'btree', 'Compliance queries (partial)', 'LOW'),
    ('idx_legal_hold', 'btree', 'Legal hold queries (partial)', 'LOW'),
    ('idx_encrypted', 'btree', 'Encrypted objects (partial)', 'LOW'),
    ('idx_version', 'btree', 'Version control (partial)', 'LOW'),
    ('idx_size_bytes', 'btree', 'Large object queries (partial)', 'LOW')
ON CONFLICT (index_name) DO NOTHING;

-- 检查索引状态
\echo 'Index Status Report:'
\echo '-------------------'
SELECT 
    e.index_name,
    e.priority,
    e.description,
    CASE 
        WHEN i.indexname IS NOT NULL THEN '✓ EXISTS'
        ELSE '✗ MISSING'
    END AS status,
    COALESCE(
        (SELECT pg_size_pretty(pg_relation_size(quote_ident(i.indexname)::regclass))),
        'N/A'
    ) AS index_size
FROM expected_indexes e
LEFT JOIN pg_indexes i 
    ON i.tablename = 's3_objects' 
    AND i.indexname = e.index_name
ORDER BY 
    CASE e.priority 
        WHEN 'HIGH' THEN 1 
        WHEN 'MEDIUM' THEN 2 
        WHEN 'LOW' THEN 3 
    END,
    e.index_name;
\echo ''

-- =====================================================
-- 3. 检查唯一约束
-- =====================================================
\echo '3. Checking unique constraints...'
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_constraint 
            WHERE conname = 'unique_bucket_key' 
            AND conrelid = 's3_objects'::regclass
        ) 
        THEN '✓ Unique constraint unique_bucket_key exists'
        ELSE '✗ WARNING: Unique constraint unique_bucket_key missing!'
    END AS status;
\echo ''

-- =====================================================
-- 4. 检查触发器
-- =====================================================
\echo '4. Checking triggers...'
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_trigger 
            WHERE tgname = 's3_objects_updated_at_trigger'
            AND tgrelid = 's3_objects'::regclass
        ) 
        THEN '✓ Trigger s3_objects_updated_at_trigger exists'
        ELSE '✗ WARNING: Auto-update trigger missing!'
    END AS status;
\echo ''

-- =====================================================
-- 5. 索引健康检查
-- =====================================================
\echo '5. Index health check...'
\echo ''

-- 检查索引膨胀
\echo 'Index Bloat Analysis:'
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    CASE 
        WHEN idx_scan = 0 THEN '⚠ NEVER USED'
        WHEN idx_scan < 100 THEN '⚠ RARELY USED'
        ELSE '✓ ACTIVE'
    END AS usage_status
FROM pg_stat_user_indexes
WHERE tablename = 's3_objects'
ORDER BY idx_scan DESC;
\echo ''

-- =====================================================
-- 6. GIN 索引特别检查
-- =====================================================
\echo '6. GIN index verification (for JSONB fields)...'
SELECT 
    i.indexname,
    i.indexdef,
    pg_size_pretty(pg_relation_size(quote_ident(i.indexname)::regclass)) AS index_size,
    CASE 
        WHEN i.indexdef LIKE '%USING gin%' THEN '✓ GIN index'
        ELSE '✗ Not GIN'
    END AS index_type
FROM pg_indexes i
WHERE i.tablename = 's3_objects'
  AND i.indexname IN ('idx_tags_gin', 'idx_user_metadata_gin');
\echo ''

-- =====================================================
-- 7. 性能建议
-- =====================================================
\echo '7. Performance recommendations...'
\echo ''

-- 检查表统计信息是否最新
\echo 'Table Statistics Status:'
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    CASE 
        WHEN last_analyze < NOW() - INTERVAL '7 days' OR last_analyze IS NULL
        THEN '⚠ Run ANALYZE s3_objects;'
        ELSE '✓ Statistics up to date'
    END AS recommendation
FROM pg_stat_user_tables
WHERE tablename = 's3_objects';
\echo ''

-- 检查表大小
\echo 'Table Size Information:'
SELECT 
    pg_size_pretty(pg_total_relation_size('s3_objects')) AS total_size,
    pg_size_pretty(pg_relation_size('s3_objects')) AS table_size,
    pg_size_pretty(pg_total_relation_size('s3_objects') - pg_relation_size('s3_objects')) AS indexes_size,
    (SELECT COUNT(*) FROM s3_objects) AS row_count;
\echo ''

-- =====================================================
-- 8. 缺失索引报告
-- =====================================================
\echo '8. Missing indexes report...'
CREATE TEMP TABLE missing_indexes AS
SELECT e.index_name, e.priority, e.description
FROM expected_indexes e
LEFT JOIN pg_indexes i 
    ON i.tablename = 's3_objects' 
    AND i.indexname = e.index_name
WHERE i.indexname IS NULL;

\echo 'Missing Indexes:'
SELECT * FROM missing_indexes ORDER BY 
    CASE priority 
        WHEN 'HIGH' THEN 1 
        WHEN 'MEDIUM' THEN 2 
        WHEN 'LOW' THEN 3 
    END;
\echo ''

-- =====================================================
-- 9. 生成修复 SQL
-- =====================================================
\echo '9. Suggested fix commands...'
\echo ''

DO $$
DECLARE
    missing_count INT;
BEGIN
    SELECT COUNT(*) INTO missing_count FROM missing_indexes WHERE priority = 'HIGH';
    
    IF missing_count > 0 THEN
        RAISE NOTICE '⚠ CRITICAL: % high-priority indexes are missing!', missing_count;
        RAISE NOTICE 'Run the following commands to create them:';
        RAISE NOTICE '';
        RAISE NOTICE 'CREATE INDEX IF NOT EXISTS idx_bucket_key ON s3_objects (bucket, object_key);';
        RAISE NOTICE 'CREATE INDEX IF NOT EXISTS idx_tags_gin ON s3_objects USING GIN (tags);';
        RAISE NOTICE 'CREATE INDEX IF NOT EXISTS idx_last_modified ON s3_objects (last_modified DESC);';
        RAISE NOTICE '';
    ELSE
        RAISE NOTICE '✓ All high-priority indexes are present!';
    END IF;
END $$;
\echo ''

-- =====================================================
-- 10. 汇总报告
-- =====================================================
\echo '========================================='
\echo 'Verification Summary'
\echo '========================================='

DO $$
DECLARE
    total_expected INT;
    total_present INT;
    high_priority_missing INT;
    coverage_pct NUMERIC;
BEGIN
    SELECT COUNT(*) INTO total_expected FROM expected_indexes;
    SELECT COUNT(*) INTO total_present 
    FROM expected_indexes e
    INNER JOIN pg_indexes i ON i.indexname = e.index_name AND i.tablename = 's3_objects';
    
    SELECT COUNT(*) INTO high_priority_missing
    FROM missing_indexes WHERE priority = 'HIGH';
    
    coverage_pct := ROUND((total_present::NUMERIC / total_expected::NUMERIC) * 100, 2);
    
    RAISE NOTICE 'Total Expected Indexes: %', total_expected;
    RAISE NOTICE 'Indexes Present: %', total_present;
    RAISE NOTICE 'Coverage: %%%', coverage_pct;
    RAISE NOTICE '';
    
    IF high_priority_missing > 0 THEN
        RAISE WARNING 'Status: ✗ FAILED - % critical indexes missing', high_priority_missing;
        RAISE NOTICE 'Action Required: Create missing high-priority indexes immediately!';
    ELSIF coverage_pct = 100 THEN
        RAISE NOTICE 'Status: ✓ PASSED - All indexes created';
    ELSE
        RAISE NOTICE 'Status: ⚠ WARNING - Some optional indexes missing';
        RAISE NOTICE 'Recommendation: Create missing indexes for optimal performance';
    END IF;
END $$;

\echo '========================================='
\echo 'Verification Complete'
\echo '========================================='
