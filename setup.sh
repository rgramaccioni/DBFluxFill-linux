#!/usr/bin/env bash
# DBFluxFill Setup (Linux)
# Downloads a portable Python 3.11 (python-build-standalone) into ./python
# and launches the text-mode installer wizard.
#
# No system Python, no system packages, no sudo required.
# No desktop session required (no Tkinter, no X11).

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
        echo "       DBFluxFill ships portable Python only for x86_64 and aarch64 Linux."
        exit 1
        ;;
esac

PYTHON_TARBALL_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/cpython-${PBS_PY_VERSION}+${PBS_RELEASE}-${PBS_TRIPLE}-install_only.tar.gz"
PYTHON_TARBALL="$SCRIPT_DIR/python-embed.tar.gz"

# ---------------------------------------------------------------
# Portable Python — skip if already installed
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

    echo "Portable Python ready: $($PYTHON_EXE --version 2>&1)"
fi

# ---------------------------------------------------------------
# Run the text-mode installer using the portable Python
# ---------------------------------------------------------------

echo
"$PYTHON_EXE" "$INSTALLER" --cli
rc=$?
if [ $rc -ne 0 ]; then
    echo
    echo "Installer exited with an error (code $rc). See above for details."
    exit $rc
fi
