#!/usr/bin/env bash
# AlphaSteg 0.5 Installer Script (macOS / Linux)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    CYAN='\033[0;36m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
else
    CYAN=''; YELLOW=''; GREEN=''; RED=''; NC=''
fi

info()  { printf "${YELLOW}%s${NC}\n" "$1"; }
ok()    { printf "${GREEN}%s${NC}\n" "$1"; }
err()   { printf "${RED}%s${NC}\n" "$1"; }

printf "${CYAN}===================================================${NC}\n"
printf "${CYAN}            AlphaSteg 0.5 Installer${NC}\n"
printf "${CYAN}===================================================${NC}\n"
echo ""

OS="$(uname -s)"
ARCH="$(uname -m)"

download() {
    # download <url> <output-file>
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$2" "$1"
    else
        err "-> Neither curl nor wget is available. Please install one and re-run."
        return 1
    fi
}

# Detect a Linux package manager install command
pkg_install() {
    # pkg_install <package...>
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y "$@"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$@"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm "$@"
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "$@"
    else
        return 1
    fi
}

# 1. Check/Install Python
info "[1/4] Checking Python installation..."
PYTHON_FOUND=false
if command -v python3 >/dev/null 2>&1; then
    # On macOS, /usr/bin/python3 is a stub unless Xcode Command Line Tools are
    # installed. Running the stub pops a GUI dialog, so detect it without running it.
    if [ "$OS" = "Darwin" ] && [ "$(command -v python3)" = "/usr/bin/python3" ] && ! xcode-select -p >/dev/null 2>&1; then
        info "-> Only Apple's Python stub was found (no Command Line Tools). A real Python will be installed."
    else
        PYTHON_FOUND=true
        ok "-> Found Python: $(python3 --version 2>&1)"
    fi
fi

if [ "$PYTHON_FOUND" = false ]; then
    info "-> Python 3 was not detected. Attempting automatic install..."
    if [ "$OS" = "Darwin" ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install python
        else
            info "-> Homebrew was not found. Downloading the official Python installer..."
            PY_PKG_DIR="$(mktemp -d)"
            download "https://www.python.org/ftp/python/3.11.8/python-3.11.8-macos11.pkg" "$PY_PKG_DIR/python_installer.pkg" || {
                err "-> Failed to download the Python installer. Please install Python 3 from https://www.python.org/downloads/ and re-run."
                exit 1
            }
            info "-> Launching the Python installer. Please complete the installer window, then quit it."
            open -W "$PY_PKG_DIR/python_installer.pkg"
            rm -rf "$PY_PKG_DIR"
            # Make the fresh install visible to this session.
            # NOTE: keep this version in sync with the .pkg URL above.
            export PATH="/Library/Frameworks/Python.framework/Versions/3.11/bin:/usr/local/bin:$PATH"
        fi
    else
        # Package names differ across distros: Arch calls it "python" (with venv
        # and pip built in), while Fedora/openSUSE bundle venv into "python3".
        if command -v apt-get >/dev/null 2>&1; then
            PY_PKGS="python3 python3-venv python3-pip"
        elif command -v pacman >/dev/null 2>&1; then
            PY_PKGS="python"
        else
            PY_PKGS="python3"
        fi
        # shellcheck disable=SC2086  # intentional word splitting
        pkg_install $PY_PKGS || {
            err "-> Could not install Python automatically. Please install Python 3 with your package manager and re-run this installer."
            exit 1
        }
    fi
    if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
        ok "-> Python installed successfully: $(python3 --version 2>&1)"
    else
        err "-> Python was not detected after installation. You may need to restart your terminal or install it manually."
        exit 1
    fi
fi

# 2. Check/Install FFmpeg
echo ""
info "[2/4] Checking FFmpeg installation..."
FFMPEG_INSTALLED=false
if command -v ffmpeg >/dev/null 2>&1; then
    FFMPEG_INSTALLED=true
    ok "-> Found system FFmpeg."
fi

if [ -x "$SCRIPT_DIR/ffmpeg" ]; then
    FFMPEG_INSTALLED=true
    ok "-> Found local FFmpeg binaries in app folder."
fi

if [ "$FFMPEG_INSTALLED" = false ]; then
    info "-> FFmpeg was not detected. Attempting install via package manager..."
    if [ "$OS" = "Darwin" ]; then
        if command -v brew >/dev/null 2>&1 && brew install ffmpeg; then
            FFMPEG_INSTALLED=true
            ok "-> FFmpeg installed via Homebrew."
        fi
    else
        if pkg_install ffmpeg 2>/dev/null; then
            FFMPEG_INSTALLED=true
            ok "-> FFmpeg installed via package manager."
        fi
    fi
fi

if [ "$FFMPEG_INSTALLED" = false ]; then
    info "-> Package manager install unavailable. Downloading portable static build..."
    TMPDIR_FF="$(mktemp -d)"
    if [ "$OS" = "Darwin" ]; then
        # evermeet.cx provides static macOS builds (x86_64; runs on Apple Silicon via Rosetta)
        if [ "$ARCH" = "arm64" ] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
            info "-> Apple Silicon detected without Rosetta 2 (required for the x86_64 FFmpeg build)."
            info "-> Installing Rosetta 2..."
            softwareupdate --install-rosetta --agree-to-license || true
        fi
        download "https://evermeet.cx/ffmpeg/getrelease/zip" "$TMPDIR_FF/ffmpeg.zip" \
            && download "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" "$TMPDIR_FF/ffprobe.zip" \
            && unzip -o -q "$TMPDIR_FF/ffmpeg.zip" -d "$TMPDIR_FF" \
            && unzip -o -q "$TMPDIR_FF/ffprobe.zip" -d "$TMPDIR_FF"
    else
        # BtbN builds (linked from ffmpeg.org) are current and checksummed, but only
        # cover x86_64/arm64. johnvansickle.com covers older ARM/x86 architectures
        # but has not published new builds since 2024.
        BTBN_BASE="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest"
        FF_VERIFY=false
        case "$ARCH" in
            x86_64)
                FF_URL="$BTBN_BASE/ffmpeg-master-latest-linux64-gpl.tar.xz"
                FF_VERIFY=true ;;
            aarch64)
                FF_URL="$BTBN_BASE/ffmpeg-master-latest-linuxarm64-gpl.tar.xz"
                FF_VERIFY=true ;;
            armv7l|armhf)
                FF_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-armhf-static.tar.xz" ;;
            i686|i386)
                FF_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-i686-static.tar.xz" ;;
            *)
                FF_URL="" ;;
        esac
        if [ -n "$FF_URL" ]; then
            FF_NAME="${FF_URL##*/}"
            if download "$FF_URL" "$TMPDIR_FF/$FF_NAME"; then
                # Verify BtbN downloads against their published SHA-256 checksums
                if [ "$FF_VERIFY" = true ] && command -v sha256sum >/dev/null 2>&1 \
                    && download "$BTBN_BASE/checksums.sha256" "$TMPDIR_FF/checksums.sha256"; then
                    if (cd "$TMPDIR_FF" && grep " $FF_NAME\$" checksums.sha256 | sha256sum -c - >/dev/null 2>&1); then
                        ok "-> Checksum verified."
                    else
                        err "-> Checksum verification failed for $FF_NAME. Discarding download."
                        rm -f "$TMPDIR_FF/$FF_NAME"
                    fi
                fi
                if [ -f "$TMPDIR_FF/$FF_NAME" ]; then
                    tar -xJf "$TMPDIR_FF/$FF_NAME" -C "$TMPDIR_FF" \
                        && find "$TMPDIR_FF" -mindepth 2 -type f -name "ffmpeg"  -exec mv {} "$TMPDIR_FF/ffmpeg"  \; \
                        && find "$TMPDIR_FF" -mindepth 2 -type f -name "ffprobe" -exec mv {} "$TMPDIR_FF/ffprobe" \;
                fi
            fi
        else
            err "-> Unsupported architecture for static FFmpeg build: $ARCH"
        fi
    fi

    if [ -f "$TMPDIR_FF/ffmpeg" ] && [ -f "$TMPDIR_FF/ffprobe" ]; then
        mv "$TMPDIR_FF/ffmpeg" "$SCRIPT_DIR/ffmpeg"
        mv "$TMPDIR_FF/ffprobe" "$SCRIPT_DIR/ffprobe"
        chmod +x "$SCRIPT_DIR/ffmpeg" "$SCRIPT_DIR/ffprobe"
        if [ "$OS" = "Darwin" ]; then
            # Clear the quarantine flag so Gatekeeper doesn't block the binaries
            xattr -d com.apple.quarantine "$SCRIPT_DIR/ffmpeg" "$SCRIPT_DIR/ffprobe" 2>/dev/null
        fi
        # Smoke test: make sure the binary actually runs on this system
        if "$SCRIPT_DIR/ffmpeg" -version >/dev/null 2>&1; then
            FFMPEG_INSTALLED=true
            ok "-> Portable FFmpeg successfully installed inside the application folder."
        else
            rm -f "$SCRIPT_DIR/ffmpeg" "$SCRIPT_DIR/ffprobe"
            err "-> The downloaded FFmpeg binary failed to run on this system. Please install FFmpeg manually and re-run."
        fi
    else
        err "-> Failed to obtain FFmpeg binaries. Please install FFmpeg manually and re-run."
    fi
    rm -rf "$TMPDIR_FF"

    if [ "$FFMPEG_INSTALLED" = false ]; then
        exit 1
    fi
fi

# 3. Create Python Virtual Environment
echo ""
info "[3/4] Setting up Python virtual environment (.venv)..."
if [ -d "$SCRIPT_DIR/.venv" ]; then
    ok "-> Virtual environment already exists."
else
    if ! python3 -m venv "$SCRIPT_DIR/.venv"; then
        # Debian/Ubuntu ship venv separately
        info "-> venv module missing. Attempting to install python3-venv..."
        pkg_install python3-venv 2>/dev/null
        if ! python3 -m venv "$SCRIPT_DIR/.venv"; then
            err "-> Failed to create virtual environment."
            exit 1
        fi
    fi
    ok "-> Virtual environment created successfully."
fi

# 4. Install Dependencies
echo ""
info "[4/4] Installing dependencies from requirements.txt..."
"$SCRIPT_DIR/.venv/bin/python" -m pip install --upgrade pip
if "$SCRIPT_DIR/.venv/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"; then
    ok "-> Dependencies installed successfully!"
else
    err "-> Failed to install dependencies."
    exit 1
fi

echo ""
printf "${GREEN}===================================================${NC}\n"
if [ "$OS" = "Darwin" ]; then
    printf "${GREEN}Installation Complete! Double-click 'run-mac.command' to start AlphaSteg.${NC}\n"
else
    printf "${GREEN}Installation Complete! Run ./run-linux.sh to start AlphaSteg.${NC}\n"
fi
printf "${GREEN}===================================================${NC}\n"
