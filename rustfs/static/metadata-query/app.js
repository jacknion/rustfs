/**
 * RustFS Metadata Query - Vue 3 Application
 * 
 * 元数据查询前端应用
 */

// Initialize dayjs
dayjs.extend(dayjs_plugin_relativeTime);
dayjs.locale('zh-cn');

const { createApp, ref, reactive, computed, onMounted } = Vue;

const app = createApp({
    setup() {
        // State
        const loading = ref(false);
        const error = ref(null);
        const result = ref(null);
        const dbStatus = ref('checking');
        const detailObj = ref(null);
        const toast = ref(null);
        const currentPage = ref(1);

        // Query parameters
        const query = reactive({
            bucket: '',
            prefix: '',
            storage_class: '',
            min_size_kb: null,
            max_size_kb: null,
            modified_after: '',
            modified_before: '',
            include_deleted: false,
            limit: 50
        });

        // Tags management
        const tags = ref([]);
        const newTag = reactive({ key: '', value: '' });
        const useFuzzySearch = ref(false); // 添加模糊搜索开关

        // Computed
        const totalPages = computed(() => {
            if (!result.value) return 1;
            return Math.ceil(result.value.metadata.total_count / query.limit);
        });

        // API base URL - detect current host
        const getApiBase = () => {
            // Use current origin for API calls
            return window.location.origin;
        };

        // Check database connection
        const checkDbStatus = async () => {
            try {
                const response = await fetch(`${getApiBase()}/rustfs/admin/v3/database/health`);
                if (response.ok) {
                    dbStatus.value = 'connected';
                } else {
                    dbStatus.value = 'disconnected';
                }
            } catch (e) {
                console.error('Database health check failed:', e);
                dbStatus.value = 'disconnected';
            }
        };

        // Build query URL
        const buildQueryUrl = (offset = 0) => {
            const params = new URLSearchParams();
            
            if (query.bucket) params.append('bucket', query.bucket);
            if (query.prefix) params.append('prefix', query.prefix);
            if (query.storage_class) params.append('storage_class', query.storage_class);
            
            if (query.min_size_kb) {
                params.append('min_size', String(query.min_size_kb * 1024));
            }
            if (query.max_size_kb) {
                params.append('max_size', String(query.max_size_kb * 1024));
            }
            
            if (query.modified_after) {
                params.append('modified_after', new Date(query.modified_after).toISOString());
            }
            if (query.modified_before) {
                params.append('modified_before', new Date(query.modified_before).toISOString());
            }
            
            if (query.include_deleted) {
                params.append('include_deleted', 'true');
            }
            
            params.append('limit', String(query.limit));
            params.append('offset', String(offset));
            
            // Add tags as JSON (精确或模糊搜索)
            if (tags.value.length > 0) {
                const tagsObj = {};
                tags.value.forEach(t => {
                    tagsObj[t.key] = t.value;
                });
                // 根据模糊搜索开关使用不同的参数
                const tagParam = useFuzzySearch.value ? 'tags_fuzzy' : 'tags';
                params.append(tagParam, JSON.stringify(tagsObj));
            }
            
            return `${getApiBase()}/rustfs/admin/v3/s3/metadata/query?${params.toString()}`;
        };

        // Search
        const search = async () => {
            loading.value = true;
            error.value = null;
            currentPage.value = 1;
            
            try {
                const url = buildQueryUrl(0);
                console.log('Query URL:', url);
                
                const response = await fetch(url);
                
                if (!response.ok) {
                    const text = await response.text();
                    throw new Error(`查询失败: ${response.status} - ${text}`);
                }
                
                result.value = await response.json();
                console.log('Query result:', result.value);
                
            } catch (e) {
                console.error('Search failed:', e);
                error.value = e.message;
                result.value = null;
            } finally {
                loading.value = false;
            }
        };

        // Go to page
        const goToPage = async (page) => {
            if (page < 1 || page > totalPages.value) return;
            
            loading.value = true;
            error.value = null;
            currentPage.value = page;
            
            try {
                const offset = (page - 1) * query.limit;
                const url = buildQueryUrl(offset);
                
                const response = await fetch(url);
                
                if (!response.ok) {
                    throw new Error(`查询失败: ${response.status}`);
                }
                
                result.value = await response.json();
                
            } catch (e) {
                error.value = e.message;
            } finally {
                loading.value = false;
            }
        };

        // Reset query
        const resetQuery = () => {
            query.bucket = '';
            query.prefix = '';
            query.storage_class = '';
            query.min_size_kb = null;
            query.max_size_kb = null;
            query.modified_after = '';
            query.modified_before = '';
            query.include_deleted = false;
            query.limit = 50;
            tags.value = [];
            result.value = null;
            error.value = null;
            currentPage.value = 1;
        };

        // Tag management
        const addTag = () => {
            if (newTag.key && newTag.value) {
                // Check for duplicate
                const exists = tags.value.some(t => t.key === newTag.key);
                if (exists) {
                    showToast('标签键已存在', 'error');
                    return;
                }
                tags.value.push({ key: newTag.key, value: newTag.value });
                newTag.key = '';
                newTag.value = '';
            }
        };

        const removeTag = (index) => {
            tags.value.splice(index, 1);
        };

        // Show detail
        const showDetail = (obj) => {
            detailObj.value = obj;
        };

        // Format helpers
        const formatSize = (bytes) => {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        };

        const formatDate = (dateStr) => {
            if (!dateStr) return '-';
            return dayjs(dateStr).format('YYYY-MM-DD HH:mm');
        };

        // Export functions
        const exportCSV = () => {
            if (!result.value || !result.value.objects.length) return;
            
            const headers = ['bucket', 'object_key', 'size_bytes', 'last_modified', 'etag', 'storage_class', 'is_deleted', 'tags'];
            const rows = result.value.objects.map(obj => [
                obj.bucket,
                obj.object_key,
                obj.size_bytes,
                obj.last_modified,
                obj.etag,
                obj.storage_class || 'STANDARD',
                obj.is_deleted ? 'true' : 'false',
                JSON.stringify(obj.tags || {})
            ]);
            
            const csv = [
                headers.join(','),
                ...rows.map(row => row.map(cell => `"${String(cell).replace(/"/g, '""')}"`).join(','))
            ].join('\n');
            
            downloadFile(csv, 'metadata-export.csv', 'text/csv');
            showToast('CSV 导出成功', 'success');
        };

        const exportJSON = () => {
            if (!result.value || !result.value.objects.length) return;
            
            const json = JSON.stringify(result.value.objects, null, 2);
            downloadFile(json, 'metadata-export.json', 'application/json');
            showToast('JSON 导出成功', 'success');
        };

        const downloadFile = (content, filename, mimeType) => {
            const blob = new Blob([content], { type: mimeType });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        };

        // Clipboard
        const copyToClipboard = async (text) => {
            try {
                await navigator.clipboard.writeText(text);
                showToast('已复制到剪贴板', 'success');
            } catch (e) {
                showToast('复制失败', 'error');
            }
        };

        // Toast notification
        const showToast = (message, type = 'success') => {
            toast.value = { message, type };
            setTimeout(() => {
                toast.value = null;
            }, 3000);
        };

        // Lifecycle
        onMounted(() => {
            checkDbStatus();
        });

        return {
            // State
            loading,
            error,
            result,
            dbStatus,
            detailObj,
            toast,
            currentPage,
            query,
            tags,
            newTag,
            useFuzzySearch,
            totalPages,
            
            // Methods
            search,
            goToPage,
            resetQuery,
            addTag,
            removeTag,
            showDetail,
            formatSize,
            formatDate,
            exportCSV,
            exportJSON,
            copyToClipboard
        };
    }
});

app.mount('#app');
