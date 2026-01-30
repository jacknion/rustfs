#!/bin/bash
# Sync existing S3 objects from filesystem to PostgreSQL
# Usage: ./sync_objects.sh

BUCKET="patrol-mis"
DATA_DIR="data/$BUCKET"
PSQL="/opt/homebrew/opt/postgresql@18/bin/psql -U old_mac -d rustfs"

# Function to get content type based on file extension
get_content_type() {
    local file="$1"
    case "${file##*.}" in
        jpg|jpeg) echo "image/jpeg" ;;
        png) echo "image/png" ;;
        gif) echo "image/gif" ;;
        mp4) echo "video/mp4" ;;
        txt) echo "text/plain" ;;
        pdf) echo "application/pdf" ;;
        wav) echo "audio/wav" ;;
        gz|gzip) echo "application/gzip" ;;
        *) echo "application/octet-stream" ;;
    esac
}

# Find all xl.meta files and process them
find "$DATA_DIR" -type f -name "xl.meta" | while read meta_file; do
    # Extract object key from path (remove data/bucket/ and /xl.meta suffix)
    object_key=$(echo "$meta_file" | sed "s|^$DATA_DIR/||" | sed 's|/xl.meta$||')
    
    # Get the directory containing the object data
    obj_dir=$(dirname "$meta_file")
    
    # Get file size (look for part.1 or main data file)
    size=0
    if [ -f "$obj_dir/part.1" ]; then
        size=$(stat -f%z "$obj_dir/part.1" 2>/dev/null || echo 0)
    fi
    
    # Get last modified time
    last_modified=$(stat -f%m "$meta_file" 2>/dev/null | xargs -I {} date -r {} '+%Y-%m-%d %H:%M:%S')
    
    # Get content type
    content_type=$(get_content_type "$object_key")
    
    # Generate fake etag (md5 hash of path)
    etag=$(echo -n "$object_key" | md5 | cut -d' ' -f1)
    
    # Insert into database
    echo "INSERT INTO rustfs.s3_objects (bucket, object_key, size_bytes, last_modified, etag, content_type) VALUES ('$BUCKET', '$object_key', $size, '$last_modified', '$etag', '$content_type') ON CONFLICT (bucket, object_key) DO NOTHING;"
done
