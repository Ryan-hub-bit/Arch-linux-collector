#!/bin/bash
# Create output directories
base_folder="$HOME"
mkdir -p "$base_folder/arch_packages/core"
mkdir -p "$base_folder/arch_packages/extra"

# Function to fetch all packages with pagination and remove duplicates
fetch_all_packages() {
  local repo=$1
  local output_file=$2
  local temp_file="${output_file}.tmp"
  local page=1
  local total_count=0
  local has_more=true
  
  > $temp_file # Clear the temp file
  
  echo "Fetching packages from $repo repository..."
  
  while $has_more; do
    echo "Fetching page $page..."
    local response=$(curl -s "https://archlinux.org/packages/search/json/?repo=$repo&page=$page")
    
    # Extract packages from current page
    echo "$response" | jq -r '.results[] | .pkgname + "," + (.pkgbase // .pkgname)' >> $temp_file
    
    # Check if there are more packages
    local this_page_count=$(echo "$response" | jq -r '.results | length')
    total_count=$((total_count + this_page_count))
    echo "Added $this_page_count packages (total so far: $total_count)"
    
    # If we got fewer than the typical page size, we've likely reached the end
    if [ "$this_page_count" -lt 250 ]; then
      has_more=false
      echo "Reached end of results (less than full page returned)"
    fi
    
    page=$((page + 1))
    
    # Add a small delay to be nice to the server
    sleep 1
  done
  
  # Remove duplicates and save to final output file
  echo "Removing duplicates..."
  sort -u $temp_file > $output_file
  actual_count=$(wc -l < $output_file)
  echo "Completed fetching $actual_count unique packages from $repo repository"
  
  # Clean up temp file
  rm $temp_file
}

# Function to remove duplicate URLs from clone_urls.txt files
remove_duplicate_urls() {
  local input_file=$1
  local temp_file="${input_file}.tmp"
  local header_file="${input_file}.header"
  
  echo "Removing duplicates from $input_file..."
  
  # Save the header (first 3 lines) to a separate file
  head -n 3 "$input_file" > "$header_file"
  
  # Extract URLs (skip header), sort, remove duplicates
  tail -n +4 "$input_file" | sort -u > "$temp_file"
  
  # Combine header and deduplicated URLs
  cat "$header_file" "$temp_file" > "$input_file"
  
  # Clean up temporary files
  rm "$header_file" "$temp_file"
  
  # Count unique URLs (excluding header)
  local count=$(tail -n +4 "$input_file" | wc -l)
  echo "File now contains $count unique repository URLs"
}

# Fetch all packages with pagination
fetch_all_packages "Core" "$HOME/arch_packages/core/packages.txt"
fetch_all_packages "Extra" "$HOME/arch_packages/extra/packages.txt"

# Generate clone URLs for core (with no duplicates)
echo "Generating clone URLs for Core repository..."
echo "" >> $HOME/arch_packages/core/clone_urls.txt
while IFS=, read -r pkgname pkgbase; do
  echo "https://gitlab.archlinux.org/archlinux/packaging/packages/${pkgbase}.git" >> $HOME/arch_packages/core/clone_urls.txt
done < $HOME/arch_packages/core/packages.txt

# Generate clone URLs for extra (with no duplicates)
echo "Generating clone URLs for Extra repository..."
echo "" >> $HOME/arch_packages/extra/clone_urls.txt
while IFS=, read -r pkgname pkgbase; do
  echo "https://gitlab.archlinux.org/archlinux/packaging/packages/${pkgbase}.git" >> $HOME/arch_packages/extra/clone_urls.txt
done < $HOME/arch_packages/extra/packages.txt

# Remove duplicate URLs from clone_urls.txt files
echo "Removing duplicate URLs from clone files..."
remove_duplicate_urls "$HOME/arch_packages/core/clone_urls.txt"
remove_duplicate_urls "$HOME/arch_packages/extra/clone_urls.txt"

echo "Script completed. All unique package information has been retrieved."
echo "Duplicate URLs have been removed from clone files."
