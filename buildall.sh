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

# Track how many packages we built
PACKAGE_COUNTER=0
# How many packages before clearing pacman cache
CLEAN_THRESHOLD=200

# GitLab access info
GITLAB_USERNAME=""
GITLAB_TOKEN=""

# ─── Functions ────────────────────────────────────────────── #

# Function to clean pacman cache safely
clean_pacman_cache() {
  echo "🧹 Cleaning pacman cache (keeping latest 3 versions)..."
  
  # Check if paccache exists
  if ! command -v paccache &>/dev/null; then
    echo "🔧 Installing pacman-contrib (provides paccache)..."
    sudo pacman -Sy --noconfirm pacman-contrib
  fi

  sudo paccache -r
}

# Function to build a package, log results, and extract ELF files
build_package() {
  local pkg_dir=$1
  local full_path
  full_path=$(realpath "$pkg_dir")

  echo "⚙️  Building package in $full_path..."

  cd "$full_path" || return
  export CC=/home/kun/llvm-project/build/bin/clang
  export CXX=/home/kun/llvm-project/build/bin/clang++

  if makepkg --syncdeps --noconfirm --needed --skippgpcheck &> build.log; then
    echo "✅ SUCCESS: $full_path" >> "$BUILD_LOG"
    cd - > /dev/null

    # Copy usable ELF files (flattened), record mapping
    find "$full_path/pkg" -type f | while read -r exe; do
      if file "$exe" | grep -q "ELF"; then
        if objdump -h "$exe" &>/dev/null; then
          out_dir="$ELF_OUTPUT_DIR/$(basename "$pkg_dir")"
          mkdir -p "$out_dir"

          base_name=$(basename "$exe")
          dest="$out_dir/$base_name"

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

    # Cleanup the built source
    echo "🧹 Cleaning up $full_path"
    chmod -R u+w "$full_path" 2>/dev/null || true
    rm -rf "$full_path"

    # Increment counter
    ((PACKAGE_COUNTER++))

    # If counter reaches threshold, clean pacman cache
    if (( PACKAGE_COUNTER >= CLEAN_THRESHOLD )); then
      clean_pacman_cache
      PACKAGE_COUNTER=0  # reset counter after cleaning
    fi

  else
    echo "❌ FAILED: $full_path" >> "$BUILD_LOG"
    cd - > /dev/null
  fi
}

# Function to process package list from a section
process_packages() {
  local section=$1
  local list_file=$2

  echo "📦 Processing $section packages..."
  mkdir -p "${section}_packages"
  cd "${section}_packages" || exit

  while read -r url; do
    [[ "$url" =~ ^#.*$ || -z "$url" ]] && continue

    # Skip already processed URLs
    if grep -Fxq "$url" "$PROGRESS_LOG"; then
      echo "⏭️  Already processed: $url"
      continue
    fi

    # Insert username and token into GitLab URL
    if [[ "$url" == https://gitlab.archlinux.org/* ]]; then
      url="${url/https:\/\//https:\/\/$GITLAB_USERNAME:$GITLAB_TOKEN@}"
    fi

    pkg_name=$(basename "$url" .git)
    echo "🌐 Cloning $pkg_name..."
    if git clone "$url" &>/dev/null; then
      if [ -d "$pkg_name" ]; then
        build_package "$pkg_name"
        echo "$url" >> "$PROGRESS_LOG"
      else
        echo "❌ FAILED TO CLONE (no dir): $pkg_name ($url)" >> "$BUILD_LOG"
        echo "$url" >> "$PROGRESS_LOG"
      fi
    else
      echo "❌ FAILED TO CLONE (git error): $pkg_name ($url)" >> "$BUILD_LOG"
      echo "$url" >> "$PROGRESS_LOG"
    fi
  done < "$list_file"

  cd ..
}

# ─── Main ─────────────────────────────────────────────────── #

process_packages "core" "$HOME/arch_packages/core/clone_urls.txt"
process_packages "extra" "$HOME/arch_packages/extra/clone_urls.txt"

# Final cleaning after everything
clean_pacman_cache

# ─── Success Rate Summary ────────────────────────────────── #

echo ""
echo "📈 Generating success rate report..."

success_count=$(grep -c "^✅ SUCCESS:" "$BUILD_LOG" || echo 0)
fail_count=$(grep -c "^❌ FAILED" "$BUILD_LOG" || echo 0)
total=$((success_count + fail_count))

if (( total > 0 )); then
  success_rate=$(awk "BEGIN {printf \"%.2f\", ($success_count/$total)*100}")
else
  success_rate=0
fi

echo "✅ Built packages: $success_count"
echo "❌ Failed packages: $fail_count"
echo "📊 Success rate: ${success_rate}%"
echo ""
echo "📝 Build log saved to: $BUILD_LOG"
echo "📜 ELF binary map saved to: $ELF_MAP"
echo "📘 Processed URLs saved to: $PROGRESS_LOG"

