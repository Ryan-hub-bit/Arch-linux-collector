#!/bin/bash

# Usage: ./check_success_failed.sh <your_file>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <file>"
  exit 1
fi

file="$1"

# Initialize counters
success=0
failed=0

# Read the file line by line
while IFS= read -r line; do
  if [[ "$line" == ✅\ SUCCESS:* ]]; then
    ((success++))
  elif [[ "$line" == ❌\ FAILED:* ]]; then
    ((failed++))
  fi
done < "$file"

# Output the result
echo "✅ SUCCESS count: $success"
echo "❌ FAILED count: $failed"

