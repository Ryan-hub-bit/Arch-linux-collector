#!/bin/bash

BUILD_DIR="$HOME/arch-build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Create the built_packages directory at the start
mkdir -p "$BUILD_DIR/built_packages"

# Create a shared directory in your home folder
mkdir -p "$HOME/shared_binaries"
echo "Created shared directory at $HOME/shared_binaries"

# Disable stripping globally in makepkg.conf (only if we can access it)
if [ -f "/etc/makepkg.conf" ] && [ -w "/etc/makepkg.conf" ]; then
    sed -i 's/OPTIONS=(strip/OPTIONS=(!strip/' /etc/makepkg.conf
else
    echo "Warning: Could not modify /etc/makepkg.conf, will try to disable stripping in individual PKGBUILDs"
fi

# Function to modify PKGBUILD to use Clang and keep debug symbols
modify_for_clang() {
    echo "Modifying PKGBUILD to use Clang and preserve debug symbols..."
    
    # Replace gcc with clang in PKGBUILD
    sed -i 's/CC=gcc/CC=clang/g' PKGBUILD
    sed -i 's/CXX=g++/CXX=clang++/g' PKGBUILD
    
    # Add environment variables to force Clang usage with simpler flags
    echo -e "\n# Modified to use Clang" >> PKGBUILD
    echo "export CC=clang" >> PKGBUILD
    echo "export CXX=clang++" >> PKGBUILD
    echo "export CPP=clang-cpp" >> PKGBUILD
    echo "export AR=llvm-ar" >> PKGBUILD
    echo "export NM=llvm-nm" >> PKGBUILD
    echo "export RANLIB=llvm-ranlib" >> PKGBUILD
    echo "export LDFLAGS=\"-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now -fuse-ld=lld\"" >> PKGBUILD
    
    # Add debug flags to CFLAGS and CXXFLAGS
    if grep -q "CFLAGS=" PKGBUILD; then
        sed -i 's/CFLAGS="/CFLAGS="-g /g' PKGBUILD
    else
        echo 'export CFLAGS="-g $CFLAGS"' >> PKGBUILD
    fi
    
    if grep -q "CXXFLAGS=" PKGBUILD; then
        sed -i 's/CXXFLAGS="/CXXFLAGS="-g /g' PKGBUILD
    else
        echo 'export CXXFLAGS="-g $CXXFLAGS"' >> PKGBUILD
    fi
    
    # Add options to keep debug symbols
    if grep -q "^options=(" PKGBUILD; then
        # Replace 'strip' with '!strip' if it exists
        sed -i 's/strip/!strip/g' PKGBUILD
        # Add !strip if it doesn't exist
        sed -i '/^options=(/s/)/ !strip)/' PKGBUILD
    else
        # Add options array if it doesn't exist
        echo "options=(!strip !debug)" >> PKGBUILD
    fi
    
    # Add debug flags to the makepkg.conf in the build directory
    if [ -f "PKGBUILD" ]; then
        echo 'OPTIONS=(!strip !debug)' > makepkg.conf
        echo 'CFLAGS="$CFLAGS -g"' >> makepkg.conf
        echo 'CXXFLAGS="$CXXFLAGS -g"' >> makepkg.conf
        echo 'BUILDENV=(!distcc color !ccache check !sign)' >> makepkg.conf
        export PKGDEST="$PWD"
    fi
    
    # For meson-based builds like systemd, we need to modify the project files
    if [ -f "meson.build" ]; then
        echo "Meson project found, adjusting build options..."
        sed -i 's/-fuse-ld=\/home\/llvm-project\/build\/bin\/ld.lld/-fuse-ld=lld/g' meson.build
        sed -i 's/-fmatch-indirect-call//g' meson.build
    fi
}

# Function to build a package
build_package() {
    local package=$1
    echo "=== Building $package with Clang ==="
    
    # Skip if already built
    if [ -f "$BUILD_DIR/built_packages/$package.done" ]; then
        echo "$package already built, skipping."
        return
    fi
    
    # Check if directory exists already
    if [ -d "$package" ]; then
        echo "Directory $package already exists, using existing directory"
        cd "$package"
    else
        # Clone the package repository
        git clone "https://gitlab.archlinux.org/archlinux/packaging/packages/$package.git"
        if [ $? -ne 0 ]; then
            echo "Failed to clone $package, skipping..."
            return
        fi
        cd "$package"
    fi
    
    # Modify PKGBUILD to use Clang
    modify_for_clang
    
    # For systemd, make additional modifications
    if [ "$package" == "systemd" ]; then
        echo "Special handling for systemd..."
        # Create a simple wrapper for clang that strips problematic flags
        cat > clang-wrapper.sh << 'EOF'
#!/bin/bash
args=()
for arg in "$@"; do
    # Skip problematic flags
    if [[ "$arg" == "-fuse-ld=/home/llvm-project/build/bin/ld.lld" ]]; then
        args+=("-fuse-ld=lld")
    elif [[ "$arg" == "-fmatch-indirect-call" ]]; then
        continue
    else
        args+=("$arg")
    fi
done
# Call the real clang with filtered arguments
exec /usr/bin/clang "${args[@]}"
EOF
        chmod +x clang-wrapper.sh
        
        # Use the wrapper
        sed -i 's/export CC=clang/export CC=$PWD\/clang-wrapper.sh/g' PKGBUILD
    fi
    
    # Build the package
    echo "Starting build of $package with Clang..."
    makepkg -s --noconfirm --skipinteg
    local build_status=$?
    
    # Track successful builds
    cd "$BUILD_DIR"
    if [ $build_status -eq 0 ]; then
        mkdir -p "$BUILD_DIR/built_packages"
        touch "$BUILD_DIR/built_packages/$package.done"
        echo "=== Successfully built $package with Clang ==="
        
        # Copy binaries to shared directory
        echo "Copying $package binaries to shared directory..."
        find "$BUILD_DIR/$package/pkg" -type f -executable -exec file {} \; | grep ELF | cut -d: -f1 | 
        while read binary; do
            binary_name="$package-$(basename "$binary")"
            cp "$binary" "$HOME/shared_binaries/$binary_name" 2>/dev/null || true
            echo "Copied $binary_name"
        done
    else
        echo "=== Failed to build $package with Clang ==="
    fi
}

# List of packages to build
PACKAGES=(
	"bash"
)
PACKAGES2=(
    # Core system utilities
    "coreutils"
    "bash"
    "util-linux"
    "findutils"
    "grep"
    "gzip"
    "sed"
    
    # System management
    "shadow"
    "procps-ng"
    "systemd"
    "cryptsetup"
    "iproute2"
    
    # Libraries and core components
    "glibc"
    "gcc-libs"
    
    # Additional utilities
    "pacman"
    "tar"
    "which"
    "file"
    "less"
)

# Build each package
for pkg in "${PACKAGES[@]}"; do
    build_package "$pkg"
    echo "----------------------------------------"
done

echo "Build process complete! Non-stripped binaries with debug symbols have been built."
echo "You can find the compiled ELF files in each package's pkg directory."
echo "Selected binaries have been copied to $HOME/shared_binaries for easy access."
echo "To access these files from the host system, you can copy them using:"
echo "  sudo cp -r /path/to/chroot$HOME/shared_binaries /path/on/host/"
