#!/usr/bin/env bash
# DBFluxFill Setup (Linux)
# Downloads a portable Python 3.11 build for inference, finds system Python for the installer GUI.

set -u

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALLER="$SCRIPT_DIR/installer.py"
PYTHON_DIR="$SCRIPT_DIR/python"
PYTHON_EXE="$PYTHON_DIR/bin/python3"

# Portable Python (python-build-standalone, distributed by Astral).
# Pinned release. To bump: pick a tagged asset at
# https://github.com/astral-sh/python-build-standalone/releases
PBS_RELEASE="20240814"
PBS_PY_VERSION="3.11.9"

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)
        PBS_TRIPLE="x86_64-unknown-linux-gnu"
        ;;
    aarch64|arm64)
        PBS_TRIPLE="aarch64-unknown-linux-gnu"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        echo "       DBFluxFill ships portable Python only for x86_64 and aarch64."
        exit 1
        ;;
esac

PYTHON_TARBALL_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/cpython-${PBS_PY_VERSION}+${PBS_RELEASE}-${PBS_TRIPLE}-install_only.tar.gz"
PYTHON_TARBALL="$SCRIPT_DIR/python-embed.tar.gz"

# ---------------------------------------------------------------
# PHASE 1 - Portable Python for inference (skip if already done)
# ---------------------------------------------------------------

if [ -x "$PYTHON_EXE" ]; then
    echo "Portable Python already set up. Skipping download."
else
    if [ -f "$PYTHON_TARBALL" ]; then
        echo "Found python-embed.tar.gz in folder. Using local copy."
    else
        echo "Downloading portable Python ${PBS_PY_VERSION} (${PBS_TRIPLE})..."
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fL --retry 3 -o "$PYTHON_TARBALL" "$PYTHON_TARBALL_URL"; then
                rm -f "$PYTHON_TARBALL"
                cat <<EOF

---------------------------------------------------------------
 Download failed. This may be due to a firewall or no internet.
---------------------------------------------------------------

 To install manually:

 1. On a machine with internet access, download this file:
    $PYTHON_TARBALL_URL

 2. Copy the downloaded tarball into this folder:
    $SCRIPT_DIR

 3. Make sure it is named exactly:
    python-embed.tar.gz

 4. Re-run this setup.sh

EOF
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -O "$PYTHON_TARBALL" "$PYTHON_TARBALL_URL"; then
                rm -f "$PYTHON_TARBALL"
                echo "Download failed (wget). See instructions above."
                exit 1
            fi
        else
            echo "ERROR: Neither curl nor wget is available. Please install one of them."
            exit 1
        fi
    fi

    echo "Unpacking portable Python..."
    rm -rf "$PYTHON_DIR"
    mkdir -p "$PYTHON_DIR"
    # The tarball contains a top-level "python/" directory; strip it.
    if ! tar -xzf "$PYTHON_TARBALL" -C "$PYTHON_DIR" --strip-components=1; then
        echo "Failed to unpack portable Python."
        exit 1
    fi
    rm -f "$PYTHON_TARBALL"

    if [ ! -x "$PYTHON_EXE" ]; then
        echo "ERROR: Portable Python extraction completed but $PYTHON_EXE was not found."
        exit 1
    fi

    echo "Portable Python ready."
fi

# ---------------------------------------------------------------
# PHASE 2 - Find system Python with Tk for the installer GUI
# ---------------------------------------------------------------

find_gui_python() {
    local candidate
    for candidate in python3 python python3.12 python3.11 python3.10 python3.9 python3.8; do
        if command -v "$candidate" >/dev/null 2>&1; then
            if "$candidate" -c "import sys; import tkinter; sys.exit(0 if sys.version_info >= (3,6) else 1)" >/dev/null 2>&1; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}

GUI_PYTHON="$(find_gui_python || true)"

if [ -z "$GUI_PYTHON" ]; then
    cat <<'EOF'

---------------------------------------------------------------
 Python 3.6+ with Tk is required to run the DBFluxFill installer.
---------------------------------------------------------------

 It does not appear to be available on this machine.

 Install Python 3 and the Tk bindings using your distribution's
 package manager. Examples:

   Debian / Ubuntu:   sudo apt install python3 python3-tk
   Fedora / RHEL:     sudo dnf install python3 python3-tkinter
   Arch Linux:        sudo pacman -S python tk
   openSUSE:          sudo zypper install python3 python3-tk

 After installing, re-run this script:

   ./setup.sh

 If your studio network blocks package mirrors, ask your IT
 department to install python3 and the python3-tk (or
 python3-tkinter) package on this machine.

EOF
    exit 1
fi

# ---------------------------------------------------------------
# Run the installer
# ---------------------------------------------------------------

echo
echo "Launching DBFluxFill Setup..."
echo
"$GUI_PYTHON" "$INSTALLER"
rc=$?
if [ $rc -ne 0 ]; then
    echo
    echo "Installer exited with an error (code $rc). See above for details."
    exit $rc
fi
