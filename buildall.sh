#!/bin/bash

# Output paths
BUILD_LOG="$HOME/arch_packages/build_summary.log"
ELF_OUTPUT_DIR="$HOME/arch_packages/elf_outputs"
ELF_MAP="$HOME/arch_packages/elf_map.txt"
PROGRESS_LOG="$HOME/arch_packages/processed_urls.txt"

mkdir -p "$ELF_OUTPUT_DIR"
> "$BUILD_LOG"
> "$ELF_MAP"
touch "$PROGRESS_LOG"

# Function to build a package, log results, and extract ELF files
build_package() {
  local pkg_dir=$1
  local full_path
  full_path=$(realpath "$pkg_dir")

  echo "Building package in $full_path..."

  cd "$pkg_dir" || return
  export CC=clang
  export CXX=clang++

  if makepkg --syncdeps --noconfirm --needed --skippgpcheck &> build.log; then
    echo "✅ SUCCESS: $full_path" >> "$BUILD_LOG"
    cd - > /dev/null

    # Copy usable ELF files (flattened), record mapping
    find "$full_path/pkg" -type f -executable | while read -r exe; do
      if file "$exe" | grep -q "ELF"; then
        if objdump -h "$exe" &>/dev/null; then
          out_dir="$ELF_OUTPUT_DIR/$(basename "$pkg_dir")"
          mkdir -p "$out_dir"

          base_name=$(basename "$exe")
          dest="$out_dir/$base_name"

          # Avoid name collisions
          i=1
          while [[ -e "$dest" ]]; do
            dest="$out_dir/${base_name}_$i"
            ((i++))
          done

          cp "$exe" "$dest"
          echo "$exe -> $(realpath --relative-to="$ELF_OUTPUT_DIR" "$dest")" >> "$ELF_MAP"
        fi
      fi
    done

    # Cleanup
    echo "🧹 Cleaning up $full_path"
    rm -rf "$full_path"

  else
    echo "❌ FAILED: $full_path" >> "$BUILD_LOG"
    cd - > /dev/null
  fi
}

# Function to process package list from a section
process_packages() {
  local section=$1
  local list_file=$2

  echo "Processing $section packages..."
  mkdir -p "${section}_packages"
  cd "${section}_packages" || exit

  while read -r url; do
    [[ "$url" =~ ^#.*$ || -z "$url" ]] && continue

    # Skip already processed URLs
    if grep -Fxq "$url" "$PROGRESS_LOG"; then
      echo "⏭️  Already processed: $url"
      continue
    fi

    pkg_name=$(basename "$url" .git)
    echo "Cloning $pkg_name..."
    git clone "$url" &>/dev/null

    if [ -d "$pkg_name" ]; then
      build_package "$pkg_name"
      echo "$url" >> "$PROGRESS_LOG"
    else
      echo "❌ FAILED TO CLONE: $pkg_name ($url)" >> "$BUILD_LOG"
    fi
  done < "$list_file"

  cd ..
}

# Example run
process_packages "core" "$HOME/arch_packages/core/clone_urls.txt"
process_packages "extra" "$HOME/arch_packages/extra/clone_urls.txt"

# Summary
echo "✅ All packages processed."
echo "📝 Build log saved to: $BUILD_LOG"
echo "📜 ELF binary map saved to: $ELF_MAP"
echo "📘 Processed URLs saved to: $PROGRESS_LOG"

