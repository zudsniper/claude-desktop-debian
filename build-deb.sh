#!/bin/bash
set -e

# Default download URL (may be outdated)
DEFAULT_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

# ANSI color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help/usage information
usage() {
    echo -e "${BLUE}Usage:${NC} sudo $0 [download_url]"
    echo
    echo -e "${BLUE}Arguments:${NC}"
    echo -e "  download_url  Optional URL to the Claude Desktop Windows installer"
    echo
    echo -e "${BLUE}Example:${NC}"
    echo -e "  sudo $0 https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
    echo
    exit 1
}

# Set download URL from command line argument or use default
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

CLAUDE_DOWNLOAD_URL="${1:-$DEFAULT_URL}"

# Show warning if using default URL
if [ "$CLAUDE_DOWNLOAD_URL" = "$DEFAULT_URL" ]; then
    echo -e "${YELLOW}⚠️  Warning: Using the default download URL which may be outdated.${NC}"
    echo -e "${YELLOW}   To get the latest version:${NC}"
    echo -e "${YELLOW}   1. Go to ${BLUE}https://claude.ai/download${YELLOW}${NC}"
    echo -e "${YELLOW}   2. Right-click the 'Windows' download button${NC}"
    echo -e "${YELLOW}   3. Select 'Copy Link'${NC}"
    echo -e "${YELLOW}   4. Run this script with the copied URL as an argument${NC}"
    echo
fi

# Check if running on a Debian-based distribution
if [ ! -f "/etc/debian_version" ]; then
    echo -e "${RED}❌ This script requires a Debian-based Linux distribution${NC}"
    echo -e "${YELLOW}This script has been tested on: Debian, Ubuntu, Linux Mint, Pop!_OS${NC}"
    exit 1
fi

# Check for root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo to install dependencies"
    exit 1
fi

# Preserve NVM path when running with sudo
if [ ! -z "$SUDO_USER" ]; then
    # Get the original user's home directory
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    
    # Check for NVM installation and add to PATH
    if [ -d "$USER_HOME/.nvm" ]; then
        echo "Found NVM installation, preserving npm/npx path..."
        
        # Find the most recent node version directory
        NVM_BIN=$(find "$USER_HOME/.nvm/versions/node" -maxdepth 2 -name "bin" -type d | sort -r | head -n 1)
        
        if [ ! -z "$NVM_BIN" ]; then
            echo "Adding $NVM_BIN to PATH"
            export PATH="$NVM_BIN:$PATH"
            
            # Verify npm and npx are now accessible
            if command -v npm &> /dev/null; then
                echo "✓ npm found at: $(which npm)"
            else
                echo "❌ npm still not accessible in PATH"
            fi
            
            if command -v npx &> /dev/null; then
                echo "✓ npx found at: $(which npx)"
            else
                echo "❌ npx still not accessible in PATH"
            fi
        fi
    fi
fi

# Print system information
echo "System Information:"
echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"
echo "Debian version: $(cat /etc/debian_version)"

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

# Check and install dependencies
echo "Checking dependencies..."
DEPS_TO_INSTALL=""

# Check system package dependencies
for cmd in p7zip wget wrestool icotool convert npx dpkg-deb; do
    if ! check_command "$cmd"; then
        case "$cmd" in
            "p7zip")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL p7zip-full"
                ;;
            "wget")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL wget"
                ;;
            "wrestool"|"icotool")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL icoutils"
                ;;
            "convert")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL imagemagick"
                ;;
            "npx")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL nodejs npm" 
                ;;
            "dpkg-deb")
                DEPS_TO_INSTALL="$DEPS_TO_INSTALL dpkg-dev"
                ;;
        esac
    fi
done

# Install system dependencies if any
if [ ! -z "$DEPS_TO_INSTALL" ]; then
    echo "Installing system dependencies: $DEPS_TO_INSTALL"
    apt update
    apt install -y $DEPS_TO_INSTALL
    echo "System dependencies installed successfully"
fi

# Check for electron - first local, then global
# Check for local electron in node_modules
if [ -f "$(pwd)/node_modules/.bin/electron" ]; then
    echo "✓ local electron found in node_modules"
    LOCAL_ELECTRON="$(pwd)/node_modules/.bin/electron"
    export PATH="$(pwd)/node_modules/.bin:$PATH"
elif ! check_command "electron"; then
    echo "Installing electron via npm..."
    # Try local installation first
    if [ -f "package.json" ]; then
        echo "Found package.json, installing electron locally..."
        npm install --save-dev electron
        if [ -f "$(pwd)/node_modules/.bin/electron" ]; then
            echo "✓ Local electron installed successfully"
            LOCAL_ELECTRON="$(pwd)/node_modules/.bin/electron"
            export PATH="$(pwd)/node_modules/.bin:$PATH"
        else
            # Fall back to global installation if local fails
            npm install -g electron
            if ! check_command "electron"; then
                echo "Failed to install electron. Please install it manually:"
                echo "npm install --save-dev electron"
                exit 1
            fi
            echo "Global electron installed successfully"
        fi
    else
        # No package.json, try global installation
        npm install -g electron
        if ! check_command "electron"; then
            echo "Failed to install electron. Please install it manually:"
            echo "npm install --save-dev electron"
            exit 1
        fi
        echo "Global electron installed successfully"
    fi
fi

PACKAGE_NAME="claude-desktop"
ARCHITECTURE="amd64"
MAINTAINER="Claude Desktop Linux Maintainers"
DESCRIPTION="Claude Desktop for Linux"
# Create working directories
WORK_DIR="$(pwd)/build"
DEB_ROOT="$WORK_DIR/deb-package"
INSTALL_DIR="$DEB_ROOT/usr"

# Clean previous build
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/icons"
mkdir -p "$INSTALL_DIR/bin"

# Install asar if needed
if ! npm list -g asar > /dev/null 2>&1; then
    echo "Installing asar package globally..."
    npm install -g asar
fi

# Download Claude Windows installer
echo "📥 Downloading Claude Desktop installer..."
CLAUDE_EXE="$WORK_DIR/Claude-Setup-x64.exe"
if ! wget -O "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
cd "$WORK_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Extract nupkg filename and version
NUPKG_PATH=$(find . -name "AnthropicClaude-*.nupkg" | head -1)
if [ -z "$NUPKG_PATH" ]; then
    echo "❌ Could not find AnthropicClaude nupkg file"
    exit 1
fi

# Extract version from the nupkg filename
VERSION=$(7z l "$CLAUDE_EXE" | grep "FileVersion:" | grep -v "\.0$" | head -n1 | grep -oP "FileVersion: \K[0-9\.]+")
if [ -z "$VERSION" ]; then
    echo "❌ Could not extract version from nupkg filename"
    exit 1
fi
echo "✓ Detected Claude version: $VERSION"

# Create a dedicated directory for nupkg extraction
mkdir -p nupkg_contents
cd nupkg_contents

# Extract the nupkg with full paths preserved
if ! 7z x -y "../$NUPKG_PATH"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi

# Verify the extraction worked and required directories exist
if [ ! -d "lib/net45/resources" ]; then
    echo "❌ Failed to find lib/net45/resources directory"
    # Check what directories were actually created
    echo "Directories found:"
    find . -type d | sort
    
    # Try to locate app.asar
    echo "Searching for app.asar:"
    find . -name "app.asar" -type f
    
    # Create the necessary directory structure manually if needed
    mkdir -p lib/net45/resources
    
    # Try to find and move app.asar file to the expected location
    APP_ASAR=$(find . -name "app.asar" -type f | head -1)
    if [ ! -z "$APP_ASAR" ]; then
        cp "$APP_ASAR" lib/net45/resources/
        echo "✓ Moved app.asar to lib/net45/resources/"
    else
        echo "❌ Could not find app.asar file"
        exit 1
    fi
fi

# Return to build directory
cd ..

echo "✓ Resources extracted"

# Extract and convert icons
echo "🎨 Processing icons..."
if ! wrestool -x -t 14 "nupkg_contents/lib/net45/claude.exe" -o claude.ico; then
    echo "❌ Failed to extract icons from exe"
    # Try to locate claude.exe
    echo "Searching for claude.exe:"
    CLAUDE_EXE_PATH=$(find nupkg_contents -name "claude.exe" -type f | head -1)
    if [ ! -z "$CLAUDE_EXE_PATH" ]; then
        echo "✓ Found claude.exe at: $CLAUDE_EXE_PATH"
        if ! wrestool -x -t 14 "$CLAUDE_EXE_PATH" -o claude.ico; then
            echo "❌ Failed to extract icons even with found claude.exe"
            exit 1
        fi
    else
        echo "❌ Could not find claude.exe"
        exit 1
    fi
fi

if ! icotool -x claude.ico; then
    echo "❌ Failed to convert icons"
    exit 1
fi
echo "✓ Icons processed"

# Map icon sizes to their corresponding extracted files
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

# Install icons
for size in 16 24 32 48 64 256; do
    icon_dir="$INSTALL_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    if [ -f "${icon_files[$size]}" ]; then
        echo "Installing ${size}x${size} icon..."
        install -Dm 644 "${icon_files[$size]}" "$icon_dir/claude-desktop.png"
    else
        echo "Warning: Missing ${size}x${size} icon"
    fi
done

# Process app.asar
mkdir -p electron-app

# Use more robust path reference for resources
RESOURCES_PATH="nupkg_contents/lib/net45/resources"

# Check if app.asar exists at the expected location
if [ ! -f "$RESOURCES_PATH/app.asar" ]; then
    echo "❌ app.asar not found at expected location: $RESOURCES_PATH/app.asar"
    
    # Try to find app.asar in extracted files
    APP_ASAR=$(find nupkg_contents -name "app.asar" -type f | head -1)
    if [ ! -z "$APP_ASAR" ]; then
        echo "✓ Found app.asar at: $APP_ASAR"
        RESOURCES_PATH=$(dirname "$APP_ASAR")
    else
        echo "❌ Could not find app.asar file"
        exit 1
    fi
fi

# Copy the files from the actual location
cp "$RESOURCES_PATH/app.asar" electron-app/

# Check for app.asar.unpacked and copy if it exists
if [ -d "$RESOURCES_PATH/app.asar.unpacked" ]; then
    cp -r "$RESOURCES_PATH/app.asar.unpacked" electron-app/
else
    echo "ℹ️ app.asar.unpacked directory not found - may not be needed"
fi

cd "$WORK_DIR/electron-app"
npx asar extract app.asar app.asar.contents

# Replace native module with stub implementation
echo "Creating stub native module..."
cat > app.asar.contents/node_modules/claude-native/index.js << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy Tray icons
mkdir -p app.asar.contents/resources
mkdir -p app.asar.contents/resources/i18n

# Use the previously determined resources path
cp ../"$RESOURCES_PATH"/Tray* app.asar.contents/resources/ 2>/dev/null || echo "Warning: Tray icons not found"
cp ../"$RESOURCES_PATH"/*-*.json app.asar.contents/resources/i18n/ 2>/dev/null || echo "Warning: i18n files not found"

# Repackage app.asar
npx asar pack app.asar.contents app.asar

# Create native module with keyboard constants
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native"
cat > "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native/index.js" << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy app files
cp app.asar "$INSTALL_DIR/lib/$PACKAGE_NAME/"
cp -r app.asar.unpacked "$INSTALL_DIR/lib/$PACKAGE_NAME/"

# Copy local electron if available
if [ ! -z "$LOCAL_ELECTRON" ]; then
    echo "Copying local electron to package..."
    cp -r "$(dirname "$LOCAL_ELECTRON")/.." "$INSTALL_DIR/lib/$PACKAGE_NAME/node_modules/"
fi

# Create desktop entry
cat > "$INSTALL_DIR/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=/usr/bin/claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF

# Create wrapper script
cat > "$INSTALL_DIR/bin/claude-desktop" << EOF
#!/bin/bash

# Load NVM if available
if [ -f "\$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="\$HOME/.nvm"
    [ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"  # This loads nvm
fi

# Launch the actual application
exec electron /usr/lib/claude-desktop/resources/app.asar "\$@"
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"

# Create control file
cat > "$DEB_ROOT/DEBIAN/control" << EOF
Package: claude-desktop
Version: $VERSION
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Depends: p7zip-full
Description: $DESCRIPTION
 Claude is an AI assistant from Anthropic.
 This package provides the desktop interface for Claude.
 .
 Supported on Debian-based Linux distributions (Debian, Ubuntu, Linux Mint, MX Linux, etc.)
EOF

# Create postinst script
cat > "$DEB_ROOT/DEBIAN/postinst" << EOF
#!/bin/sh
set -e

# Function to check for nodejs and npm
check_node_npm() {
    # Check for NVM installation
    if [ -f "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    fi

    # Use which to find executables in both system and nvm paths
    NODEJS_PATH=$(which node 2>/dev/null)
    NPM_PATH=$(which npm 2>/dev/null)

    if [ -n "$NODEJS_PATH" ]; then
        echo "Found Node.js at: $NODEJS_PATH"
    else
        echo "WARNING: nodejs not found in PATH"
        echo "Claude Desktop requires Node.js to function properly."
        echo "Please install Node.js using one of these methods:"
        echo ""
        echo "1. System package (Debian/Ubuntu):"
        echo "   sudo apt update && sudo apt install nodejs npm"
        echo ""
        echo "2. Using NVM (recommended for development):"
        echo "   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash"
        echo "   source ~/.bashrc"
        echo "   nvm install --lts"
        echo ""
    fi

    # Check for npm in PATH (after loading nvm if available)
    if [ -n "$NPM_PATH" ]; then
        echo "Found npm at: $NPM_PATH"
    else
        echo "WARNING: npm not found in PATH"
        echo "Claude Desktop requires npm to function properly."
        echo "Please install npm using one of these methods:"
        echo ""
        echo "1. System package (Debian/Ubuntu):"
        echo "   sudo apt update && sudo apt install npm"
        echo ""
        echo "2. Using NVM (automatically installs npm with Node.js):"
        echo "   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash"
        echo "   source ~/.bashrc"
        echo "   nvm install --lts"
        echo ""
    fi
}

# Function to check for electron
check_electron() {
    if ! command -v electron &> /dev/null; then
        echo "WARNING: electron not found in PATH"
        echo "Claude Desktop requires electron to function properly."
        echo "Please install electron using:"
        echo "  npm install -g electron"
        echo ""
    else
        echo "Found electron at: $(which electron)"
    fi
}

case "\$1" in
    configure)
        # Check for nodejs, npm, and electron when configuring the package
        check_node_npm
        check_electron
        ;;
    abort-upgrade|abort-remove|abort-deconfigure)
        # No specific actions needed for these cases
        ;;
    *)
        echo "postinst called with unknown argument '\$1'" >&2
        exit 1
        ;;
esac

exit 0
EOF

# Make postinst script executable
chmod +x "$DEB_ROOT/DEBIAN/postinst"

# Build .deb package
echo "🖹 Building .deb package..."
DEB_FILE="$WORK_DIR/claude-desktop_${VERSION}_${ARCHITECTURE}.deb"

if ! dpkg-deb --build "$DEB_ROOT" "$DEB_FILE"; then
    echo "❌ Failed to build .deb package"
    exit 1
fi

if [ -f "$DEB_FILE" ]; then
    echo "✓ Package built successfully at: $DEB_FILE"
    echo "🎉 Done! You can now install the package with: sudo dpkg -i $DEB_FILE"
else
    echo "❌ Package file not found at expected location: $DEB_FILE"
    exit 1
fi
