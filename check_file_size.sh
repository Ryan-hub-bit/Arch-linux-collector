#!/bin/bash

# Folder to check
FOLDER=${1:-"$HOME/arch_packages"}

# Check if folder exists
if [[ ! -d "$FOLDER" ]]; then
  echo "❌ Error: Folder '$FOLDER' does not exist."
  exit 1
fi

echo "📂 Checking file size distribution in: $FOLDER"
echo

# Initialize counters
count_0_1k=0
count_1k_10k=0
count_10k_100k=0
count_100k_1m=0
count_1m_10m=0
count_10m_100m=0
count_100m_plus=0

# Scan all files
while IFS= read -r -d '' file; do
  size=$(stat -c%s "$file")  # size in bytes

  if (( size < 1024 )); then
    ((count_0_1k++))
  elif (( size < 10240 )); then
    ((count_1k_10k++))
  elif (( size < 102400 )); then
    ((count_10k_100k++))
  elif (( size < 1048576 )); then
    ((count_100k_1m++))
  elif (( size < 10485760 )); then
    ((count_1m_10m++))
  elif (( size < 104857600 )); then
    ((count_10m_100m++))
  else
    ((count_100m_plus++))
  fi
done < <(find "$FOLDER" -type f -print0)

# Print result
echo "📊 File size distribution:"
echo "--------------------------------------"
echo "0      - 1 KB        : $count_0_1k files"
echo "1 KB   - 10 KB       : $count_1k_10k files"
echo "10 KB  - 100 KB      : $count_10k_100k files"
echo "100 KB - 1 MB        : $count_100k_1m files"
echo "1 MB   - 10 MB       : $count_1m_10m files"
echo "10 MB  - 100 MB      : $count_10m_100m files"
echo "> 100 MB             : $count_100m_plus files"
echo "--------------------------------------"
echo
echo "✅ Done."

