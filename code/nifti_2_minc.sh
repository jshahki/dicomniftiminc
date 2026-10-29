#!/bin/bash

#SBATCH --job-name=nifti2minc
#SBATCH --account=st-toddwood-1
#SBATCH --nodes=1
#SBATCH --time=168:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --output=logs/nifti2minc_%A_%a.out
#SBATCH --error=logs/nifti2minc_%A_%a.err

set -euo pipefail

# ==================================================
# MODULES AND PATHS
# ==================================================

module purge
module load gcc/9.4.0
module load apptainer/1.3.1

REPO_DIR="/scratch/st-toddwood-1/$USER/dcm_2_nifti_2_minc"
PARTICIPANTS="$REPO_DIR/data/participants.tsv"
DERIVATIVES_DIR="$REPO_DIR/derivatives"

MINC_IMAGE="$REPO_DIR/tools/minc-toolkit_1.9.18.sif"

# ==================================================
# READ PARTICIPANTS
# ==================================================

if [[ ! -f "$PARTICIPANTS" ]]; then
    echo "ERROR: Participants file not found: $PARTICIPANTS"
    exit 1
fi

mapfile -t SUBJECTS < <(
    tail -n +2 "$PARTICIPANTS" |
    cut -f1 |
    tr -d '\r' |
    sed '/^$/d'
)

TASK_ID="${SLURM_ARRAY_TASK_ID:-0}"
SUBJECT="${SUBJECTS[$TASK_ID]:-}"

if [[ -z "$SUBJECT" ]]; then
    echo "ERROR: No subject found for array index $TASK_ID"
    exit 1
fi

# ==================================================
# SUBJECT PATHS
# ==================================================

SUBJECT_DERIV_DIR="$DERIVATIVES_DIR/$SUBJECT"
NIFTI_DIR="$SUBJECT_DERIV_DIR/NIfTI"
MNC_DIR="$SUBJECT_DERIV_DIR/MNC"

STATUS_DIR="$REPO_DIR/logs/status"
STATUS_FILE="$STATUS_DIR/${SUBJECT}_nifti2minc_SUCCESS.txt"

# ==================================================
# LOGGING
# ==================================================

START_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"
START_EPOCH=$(date +%s)

echo "=========================================="
echo "NIFTI TO MINC CONVERSION"
echo "Subject: $SUBJECT"
echo "Job ID: ${SLURM_JOB_ID:-unknown}"
echo "Array task: $TASK_ID"
echo "Host: $(hostname)"
echo "Started: $START_TIME"
echo "=========================================="

# ==================================================
# CHECK REQUIREMENTS
# ==================================================

if [[ ! -s "$MINC_IMAGE" ]]; then
    echo "ERROR: MINC container not found: $MINC_IMAGE"
    exit 1
fi

if [[ ! -d "$NIFTI_DIR" ]]; then
    echo "ERROR: NIfTI directory not found: $NIFTI_DIR"
    exit 1
fi

if ! command -v apptainer >/dev/null 2>&1; then
    echo "ERROR: Apptainer is unavailable."
    exit 1
fi

mkdir -p "$MNC_DIR" "$STATUS_DIR"

# ==================================================
# FIND NIFTI FILES
# ==================================================

shopt -s nullglob
NIFTI_FILES=("$NIFTI_DIR"/*.nii.gz)
shopt -u nullglob

if (( ${#NIFTI_FILES[@]} == 0 )); then
    echo "ERROR: No .nii.gz files found in $NIFTI_DIR"
    exit 1
fi

echo "Input directory: $NIFTI_DIR"
echo "Output directory: $MNC_DIR"
echo "Found ${#NIFTI_FILES[@]} NIfTI files."

# ==================================================
# CONVERT NIFTI TO MINC
# ==================================================

CONVERTED=0
SKIPPED=0

for NIFTI_FILE in "${NIFTI_FILES[@]}"; do

    FILENAME="$(basename "$NIFTI_FILE")"
    STEM="${FILENAME%.nii.gz}"
    MNC_FILE="$MNC_DIR/${STEM}.mnc"

    echo "------------------------------------------"
    echo "Input:  $FILENAME"
    echo "Output: ${STEM}.mnc"

    # Never overwrite an existing result.
    if [[ -e "$MNC_FILE" ]]; then
        echo "SKIPPING: Output already exists."
        ((SKIPPED += 1))
        continue
    fi

    CONVERT_START=$(date +%s)

    # Bind the subject directories into the container.
    # nii2mnc accepts input .nii.gz files directly.
    if apptainer exec \
        --bind "$NIFTI_DIR:$NIFTI_DIR:ro" \
        --bind "$MNC_DIR:$MNC_DIR" \
        "$MINC_IMAGE" \
        /opt/minc/1.9.18/bin/nii2mnc \
        "$NIFTI_FILE" "$MNC_FILE"; then

        if [[ ! -s "$MNC_FILE" ]]; then
            echo "ERROR: Output is missing or empty: $MNC_FILE"
            exit 1
        fi

        echo "SUCCESS: $MNC_FILE"
        echo "Duration: $(($(date +%s) - CONVERT_START)) seconds"

        ((CONVERTED += 1))

    else
        rc=$?
        echo "ERROR: Conversion failed for $NIFTI_FILE"
        echo "Exit code: $rc"
        exit "$rc"
    fi

done

# ==================================================
# VERIFY OUTPUTS
# ==================================================

shopt -s nullglob
MNC_FILES=("$MNC_DIR"/*.mnc)
shopt -u nullglob

if (( ${#MNC_FILES[@]} == 0 )); then
    echo "ERROR: No MNC files found in $MNC_DIR"
    exit 1
fi

# ==================================================
# STATUS LOG
# ==================================================

END_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"
END_EPOCH=$(date +%s)
TOTAL_RUNTIME=$((END_EPOCH - START_EPOCH))

{
    echo "Subject: $SUBJECT"
    echo "Job ID: ${SLURM_JOB_ID:-unknown}"
    echo "Started: $START_TIME"
    echo "Completed: $END_TIME"
    echo "Newly converted: $CONVERTED"
    echo "Skipped existing: $SKIPPED"
    echo "Total MNC files: ${#MNC_FILES[@]}"
    echo "Output directory: $MNC_DIR"
    echo "Runtime seconds: $TOTAL_RUNTIME"
} > "$STATUS_FILE"

echo "=========================================="
echo "CONVERSION COMPLETED SUCCESSFULLY"
echo "Subject: $SUBJECT"
echo "Newly converted: $CONVERTED"
echo "Skipped existing: $SKIPPED"
echo "Total MNC files: ${#MNC_FILES[@]}"
echo "Output: $MNC_DIR"
echo "Finished: $END_TIME"
echo "Runtime: $TOTAL_RUNTIME seconds"
echo "=========================================="
