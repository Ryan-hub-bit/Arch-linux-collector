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

# GitLab access info
GITLAB_USERNAME=""
GITLAB_TOKEN=""

# Parallel settings
MAX_JOBS=8

# Track built packages
PACKAGE_COUNTER=0
CLEAN_THRESHOLD=200

# ─── Functions ────────────────────────────────────────────── #

# Function to wait until running background jobs < MAX_JOBS
wait_for_jobs() {
  while (( $(jobs -r | wc -l) >= MAX_JOBS )); do
    sleep 1
  done
}

# Function to clean pacman cache safely
clean_pacman_cache() {
  echo "🧹 Cleaning pacman cache (keeping latest 3 versions)..."
  
  if ! command -v paccache &>/dev/null; then
    echo "🔧 Installing pacman-contrib (provides paccache)..."
    sudo pacman -Sy --noconfirm pacman-contrib
  fi

  sudo paccache -r
}

# Function to clone a package repo
clone_package() {
  local url="$1"
  local section_dir="$2"

  url="${url/https:\/\//https:\/\/$GITLAB_USERNAME:$GITLAB_TOKEN@}"
  local pkg_name
  pkg_name=$(basename "$url" .git)

  echo "🌐 Cloning $pkg_name..."

  if git clone "$url" "$section_dir/$pkg_name" &>/dev/null; then
    echo "✅ CLONE SUCCESS: $pkg_name" | tee -a "$BUILD_LOG"
    echo "$url" >> "$PROGRESS_LOG"
  else
    echo "❌ CLONE FAILED: $pkg_name ($url)" | tee -a "$BUILD_LOG"
    echo "$url" >> "$PROGRESS_LOG"
  fi
}

# Function to build a package
build_package() {
  local pkg_dir=$1
  local full_path
  full_path=$(realpath "$pkg_dir")

  echo "⚙️  Building package in $full_path..."

  cd "$full_path" || return
  export CC=/home/kun/llvm-project/build/bin/clang
  export CXX=/home/kun/llvm-project/build/bin/clang++

  if makepkg --syncdeps --noconfirm --needed --skippgpcheck &> build.log; then
    echo "✅ BUILD SUCCESS: $full_path" | tee -a "$BUILD_LOG"
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

    echo "🧹 Cleaning up $full_path"
    chmod -R u+w "$full_path" 2>/dev/null || true
    rm -rf "$full_path"

    ((PACKAGE_COUNTER++))
    if (( PACKAGE_COUNTER >= CLEAN_THRESHOLD )); then
      clean_pacman_cache
      PACKAGE_COUNTER=0
    fi
  else
    echo "❌ BUILD FAILED: $full_path" | tee -a "$BUILD_LOG"
    cd - > /dev/null
  fi
}

# Process all packages for one section
process_packages() {
  local section=$1
  local list_file=$2

  echo "📦 Processing $section packages..."
  local section_dir="${section}_packages"
  mkdir -p "$section_dir"
  cd "$section_dir" || exit

  # ─── Clone Phase ───
  echo "🌐 Cloning all packages for $section..."
  while read -r url; do
    [[ "$url" =~ ^#.*$ || -z "$url" ]] && continue

    if grep -Fxq "$url" "$PROGRESS_LOG"; then
      echo "⏭️  Already processed: $url"
      continue
    fi

    wait_for_jobs
    clone_package "$url" "$PWD" &

  done < "$list_file"

  wait
  echo "✅ Cloning done for $section!"

  # ─── Build Phase ───
  echo "⚙️  Building all packages for $section..."
  for pkg_dir in */; do
    wait_for_jobs
    build_package "$pkg_dir" &
  done

  wait
  echo "✅ Building done for $section!"

  cd ..
}

# ─── Main ─────────────────────────────────────────────────── #

process_packages "core" "$HOME/arch_packages/core/clone_urls.txt"
process_packages "extra" "$HOME/arch_packages/extra/clone_urls.txt"

# Final cache clean
clean_pacman_cache

# ─── Success Rate Summary ────────────────────────────────── #

echo ""
echo "📈 Generating success rate report..."

clone_success=$(grep -c "^✅ CLONE SUCCESS:" "$BUILD_LOG" || echo 0)
clone_failed=$(grep -c "^❌ CLONE FAILED:" "$BUILD_LOG" || echo 0)
build_success=$(grep -c "^✅ BUILD SUCCESS:" "$BUILD_LOG" || echo 0)
build_failed=$(grep -c "^❌ BUILD FAILED:" "$BUILD_LOG" || echo 0)

echo "🔹 Clone success: $clone_success"
echo "🔹 Clone failed:  $clone_failed"
echo "🔸 Build success: $build_success"
echo "🔸 Build failed:  $build_failed"

total_clone=$((clone_success + clone_failed))
total_build=$((build_success + build_failed))

if (( total_clone > 0 )); then
  clone_rate=$(awk "BEGIN {printf \"%.2f\", ($clone_success/$total_clone)*100}")
else
  clone_rate=0
fi

if (( total_build > 0 )); then
  build_rate=$(awk "BEGIN {printf \"%.2f\", ($build_success/$total_build)*100}")
else
  build_rate=0
fi

echo "📊 Clone success rate: ${clone_rate}%"
echo "📊 Build success rate: ${build_rate}%"
echo ""
echo "📝 Build log saved to: $BUILD_LOG"
echo "📜 ELF binary map saved to: $ELF_MAP"
echo "📘 Processed URLs saved to: $PROGRESS_LOG"

