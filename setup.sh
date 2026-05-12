#!/usr/bin/env bash
# DBFluxFill Setup (Linux)
# Downloads a portable Miniforge3 Python distribution into ./python and
# launches the installer GUI using that same Python. Miniforge3 includes
# Tcl/Tk so we do not depend on any system Python or system tkinter package.

set -u

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALLER="$SCRIPT_DIR/installer.py"
PYTHON_DIR="$SCRIPT_DIR/python"
PYTHON_EXE="$PYTHON_DIR/bin/python3"

# Miniforge3 release (conda-forge). To bump: pick a tagged release from
# https://github.com/conda-forge/miniforge/releases (use a non-prerelease tag).
MINIFORGE_RELEASE="26.3.2-0"

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)
        MINIFORGE_ASSET="Miniforge3-Linux-x86_64.sh"
        ;;
    aarch64|arm64)
        MINIFORGE_ASSET="Miniforge3-Linux-aarch64.sh"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        echo "       DBFluxFill ships portable Python only for x86_64 and aarch64 Linux."
        exit 1
        ;;
esac

MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_RELEASE}/${MINIFORGE_ASSET}"
MINIFORGE_INSTALLER="$SCRIPT_DIR/miniforge-installer.sh"

# ---------------------------------------------------------------
# Portable Python (Miniforge3) — skip if already installed
# ---------------------------------------------------------------

if [ -x "$PYTHON_EXE" ]; then
    echo "Portable Python already set up. Skipping download."
else
    if [ -f "$MINIFORGE_INSTALLER" ]; then
        echo "Found ${MINIFORGE_ASSET} in folder. Using local copy."
    else
        echo "Downloading Miniforge3 ${MINIFORGE_RELEASE} (${ARCH})..."
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fL --retry 3 -o "$MINIFORGE_INSTALLER" "$MINIFORGE_URL"; then
                rm -f "$MINIFORGE_INSTALLER"
                cat <<EOF

---------------------------------------------------------------
 Download failed. This may be due to a firewall or no internet.
---------------------------------------------------------------

 To install manually:

 1. On a machine with internet access, download this file:
    $MINIFORGE_URL

 2. Copy the downloaded installer into this folder:
    $SCRIPT_DIR

 3. Make sure it is named exactly:
    miniforge-installer.sh

 4. Re-run this setup.sh

EOF
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -O "$MINIFORGE_INSTALLER" "$MINIFORGE_URL"; then
                rm -f "$MINIFORGE_INSTALLER"
                echo "Download failed (wget). See instructions above."
                exit 1
            fi
        else
            echo "ERROR: Neither curl nor wget is available. Please install one of them."
            exit 1
        fi
    fi

    echo "Unpacking Miniforge3 into ${PYTHON_DIR} (this takes ~30s)..."
    rm -rf "$PYTHON_DIR"
    # -b: batch mode (auto-accept license, no prompts).
    # -p: target prefix (where the Python distribution is unpacked).
    # -s: skip running conda init (we don't want to touch the user's shell rc).
    # Output is redirected; on failure we re-show it for debugging.
    INSTALL_LOG="$(mktemp -t miniforge-install.XXXXXX.log)"
    if ! bash "$MINIFORGE_INSTALLER" -b -s -p "$PYTHON_DIR" > "$INSTALL_LOG" 2>&1; then
        echo "ERROR: Miniforge3 installer failed. Last output:"
        echo "---"
        tail -n 40 "$INSTALL_LOG"
        echo "---"
        rm -f "$INSTALL_LOG"
        exit 1
    fi
    rm -f "$INSTALL_LOG"
    rm -f "$MINIFORGE_INSTALLER"

    if [ ! -x "$PYTHON_EXE" ]; then
        echo "ERROR: Miniforge3 installed but $PYTHON_EXE was not found."
        exit 1
    fi

    echo "Portable Python ready: $($PYTHON_EXE --version 2>&1)"
fi

# ---------------------------------------------------------------
# Pin Python to 3.11 (the version the project is written for)
#
# Miniforge3 ships a fairly new default Python (currently 3.13).
# Tkinter on Python 3.13 from conda-forge has been observed to
# segfault inside the installer on some distros, and several
# pip-pinned dependencies in installer.py (torch 2.6.0+cu124,
# transformers, accelerate, ...) only publish wheels up to 3.12.
# Forcing Python 3.11 in the base env gives us a known-good runtime.
# ---------------------------------------------------------------

CONDA_EXE="$PYTHON_DIR/bin/conda"
if ! "$PYTHON_EXE" -c "import sys; sys.exit(0 if sys.version_info[:2]==(3,11) else 1)" 2>/dev/null; then
    if [ ! -x "$CONDA_EXE" ]; then
        echo "ERROR: $CONDA_EXE not found; cannot pin Python version."
        exit 1
    fi
    echo "Pinning portable Python to 3.11 (this takes ~30-60s, downloads ~80 MB)..."
    PIN_LOG="$(mktemp -t miniforge-pin.XXXXXX.log)"
    if ! "$CONDA_EXE" install -n base -y -c conda-forge "python=3.11" > "$PIN_LOG" 2>&1; then
        echo "ERROR: Failed to pin Python 3.11. Last output:"
        echo "---"
        tail -n 40 "$PIN_LOG"
        echo "---"
        rm -f "$PIN_LOG"
        exit 1
    fi
    rm -f "$PIN_LOG"
    echo "Pinned: $($PYTHON_EXE --version 2>&1)"
fi

# ---------------------------------------------------------------
# Verify the portable Python can open a Tk window
# ---------------------------------------------------------------

if ! "$PYTHON_EXE" -c "import tkinter" >/dev/null 2>&1; then
    cat <<EOF

ERROR: Portable Python is missing the tkinter module.

  This is unexpected — Miniforge3 should ship with Tcl/Tk included.
  Try deleting the python/ folder and re-running setup.sh:

      rm -rf "$PYTHON_DIR"
      ./setup.sh

EOF
    exit 1
fi

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    cat <<EOF

WARNING: No DISPLAY or WAYLAND_DISPLAY is set.

  The installer wizard is a graphical (Tk) application and needs an
  open desktop session to render. If you are running over plain SSH,
  reconnect with X11 forwarding (ssh -X) or run setup.sh from a local
  terminal on the workstation.

  Trying to launch anyway in case a display is reachable...

EOF
fi

# ---------------------------------------------------------------
# Run the installer using the portable Python
# ---------------------------------------------------------------

echo
echo "Launching DBFluxFill Setup..."
echo
"$PYTHON_EXE" "$INSTALLER"
rc=$?
if [ $rc -ne 0 ]; then
    echo
    echo "Installer exited with an error (code $rc). See above for details."
    exit $rc
fi
