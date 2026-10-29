#!/bin/bash

set -euo pipefail

# ==================================================
# PATHS
# ==================================================

SCRATCH_DIR="/scratch/st-toddwood-1/$USER"
REPO_DIR="$SCRATCH_DIR/dicom_2_nifti_2_minc"

TOOLS_DIR="$REPO_DIR/tools"
LOG_DIR="$REPO_DIR/logs"
DERIVATIVES_DIR="$REPO_DIR/derivatives"
CACHE_DIR="$REPO_DIR/cache"

# MINC Toolkit container
MINC_VERSION="1.9.18"
MINC_IMAGE="$TOOLS_DIR/minc-toolkit_${MINC_VERSION}.sif"
MINC_DOWNLOAD_URL="docker://nistmni/minc-toolkit:${MINC_VERSION}"
MINC_NIfTI2MINC="/opt/minc/${MINC_VERSION}/bin/nifti2minc"

# dcm2niix download
DCM2NIIX_ARCHIVE="$TOOLS_DIR/dcm2niix_lnx.zip"
DCM2NIIX_URL="https://github.com/rordenlab/dcm2niix/releases/latest/download/dcm2niix_lnx.zip"

# Apptainer cache and temporary build directory
APPTAINER_CACHE="$CACHE_DIR/apptainer"
APPTAINER_TMP="$CACHE_DIR/apptainer_tmp"

# ==================================================
# CREATE DIRECTORIES
# ==================================================

mkdir -p \
    "$TOOLS_DIR" \
    "$LOG_DIR" \
    "$DERIVATIVES_DIR" \
    "$CACHE_DIR" \
    "$APPTAINER_CACHE" \
    "$APPTAINER_TMP"

LOG_FILE="$LOG_DIR/setup_login_$(date +%Y%m%d_%H%M%S).log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "DICOM2NIFTI2MINC SETUP"
echo "User: $USER"
echo "Host: $(hostname)"
echo "Start: $(date)"
echo "Repository: $REPO_DIR"
echo "=========================================="

# ==================================================
# CHECK BASIC DEPENDENCIES
# ==================================================

for CMD in curl unzip; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $CMD"
        exit 1
    fi
done

# ==================================================
# LOAD APPTAINER
# ==================================================

if ! type module >/dev/null 2>&1; then
    echo "ERROR: Environment Modules/Lmod is unavailable."
    echo "Load the cluster environment before running setup."
    exit 1
fi

echo "Loading Apptainer module..."

module load apptainer/1.3.1

if ! command -v apptainer >/dev/null 2>&1; then
    echo "ERROR: Apptainer is unavailable after loading its module."
    exit 1
fi

apptainer --version

export APPTAINER_CACHEDIR="$APPTAINER_CACHE"
export APPTAINER_TMPDIR="$APPTAINER_TMP"

# ==================================================
# INSTALL DCM2NIIX
# ==================================================

echo
echo "=========================================="
echo "STAGE 1: DCM2NIIX"
echo "=========================================="

if [[ -x "$TOOLS_DIR/dcm2niix" ]]; then

    echo "Existing dcm2niix executable found."
    echo "Verifying installation..."

    "$TOOLS_DIR/dcm2niix" -h

else

    echo "Downloading dcm2niix..."
    curl -fL --retry 3 "$DCM2NIIX_URL" -o "$DCM2NIIX_ARCHIVE"

    echo "Extracting dcm2niix..."
    unzip -o "$DCM2NIIX_ARCHIVE" -d "$TOOLS_DIR"

    if [[ ! -f "$TOOLS_DIR/dcm2niix" ]]; then
        echo "ERROR: dcm2niix was not found after extraction."
        exit 1
    fi

    chmod +x "$TOOLS_DIR/dcm2niix"

    echo "Verifying dcm2niix..."
    "$TOOLS_DIR/dcm2niix" -h

fi

echo "dcm2niix is ready: $TOOLS_DIR/dcm2niix"

# ==================================================
# INSTALL MINC TOOLKIT CONTAINER
# ==================================================

echo
echo "=========================================="
echo "STAGE 2: MINC TOOLKIT"
echo "=========================================="

if [[ -s "$MINC_IMAGE" ]]; then

    echo "Existing MINC container found:"
    echo "$MINC_IMAGE"

else

    echo "Downloading MINC Toolkit container..."
    echo "Image: $MINC_DOWNLOAD_URL"
    echo "Destination: $MINC_IMAGE"

    # Download to a temporary file so an interrupted
    # download does not leave a partially named final image.
    MINC_IMAGE_TMP="$TOOLS_DIR/.minc-toolkit_${MINC_VERSION}.tmp.sif"

    rm -f "$MINC_IMAGE_TMP"

    if apptainer pull "$MINC_IMAGE_TMP" "$MINC_DOWNLOAD_URL"; then

        if [[ ! -s "$MINC_IMAGE_TMP" ]]; then
            echo "ERROR: Downloaded MINC image is empty."
            rm -f "$MINC_IMAGE_TMP"
            exit 1
        fi

        mv "$MINC_IMAGE_TMP" "$MINC_IMAGE"

    else
        rc=$?
        echo "ERROR: Failed to download MINC Toolkit container."
        rm -f "$MINC_IMAGE_TMP"
        exit "$rc"
    fi

fi

# ==================================================
# VERIFY MINC TOOLKIT
# ==================================================

echo
echo "Verifying MINC Toolkit container..."

if ! apptainer exec "$MINC_IMAGE" test -x "$MINC_NIfTI2MINC"; then
    echo "ERROR: nii2mnc executable not found in the container:"
    echo "$MINC_NIfTI2MINC"
    exit 1
fi

echo "MINC converter found:"
echo "$MINC_NIfTI2MINC"

if ! apptainer exec "$MINC_IMAGE" "$MINC_NIfTI2MINC" -version; then
    echo "ERROR: nii2mnc verification failed."
    exit 1
fi

echo "MINC Toolkit is ready."
echo "Container: $MINC_IMAGE"

# ==================================================
# FINAL SUMMARY
# ==================================================

echo
echo "=========================================="
echo "SETUP COMPLETED SUCCESSFULLY"
echo "=========================================="
echo "Repository: $REPO_DIR"
echo
echo "DICOM -> NIfTI:"
echo "  $TOOLS_DIR/dcm2niix"
echo
echo "NIfTI -> MINC:"
echo "  $MINC_IMAGE"
echo "  $MINC_NIfTI2MINC"
echo
echo "Apptainer cache:"
echo "  $APPTAINER_CACHE"
echo
echo "Setup log:"
echo "  $LOG_FILE"
echo
echo "Completed: $(date)"
echo "=========================================="

cd "$REPO_DIR"
