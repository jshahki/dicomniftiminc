# dicom2nifti2minc

# Steps to Run the Pipeline

## Software Setup

To begin, please log onto Sockeye (https://ondemand.arc.ubc.ca/pun/sys/dashboard/) and open the Terminal window.

In the Terminal window above, please run the following code:

```sh
SCRATCH_DIR="/scratch/st-toddwood-1/$USER"

mkdir -p "$SCRATCH_DIR"

cd "$SCRATCH_DIR"

git clone -b dicom2nifti2minc_Version-1.00 --single-branch https://github.com/jshahki/dicom2nifti2minc.git

cd /scratch/st-toddwood-1/$USER/dicom2nifti2minc

```

Then run the following:

```sh

cd /scratch/st-toddwood-1/$USER/dicom2nifti2minc

source ./code/dicom2nifti2minc_setup.sh

```

Please ensure to keep the Terminal window open while this process completes.

## Converting scans from DICOM to NIfTI

After uploading your data and listing your to-be-converted subjects in the participants.tsv file, please run the following code in the Terminal window:

```sh
cd /scratch/st-toddwood-1/$USER/dicom2nifti2minc
git pull

PARTICIPANTS_FILE="./data/participants.tsv"
SUB_SIZE=1  # Subjects per job

# Read subject IDs from file (ignore header)
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS_FILE" | cut -f1 | tr -d '\r' | sed '/^$/d')

N_SUBJECTS=${#SUBJECTS[@]}
ARRAY_LENGTH=$(( (N_SUBJECTS + SUB_SIZE - 1) / SUB_SIZE ))

echo "Found $N_SUBJECTS subjects. Launching array with $ARRAY_LENGTH jobs."

sbatch --array=0-$((ARRAY_LENGTH - 1)) ./code/dicom2nifti.sh
```

Once the conversion is completed, you can access each subjects' `.nii.gz` files in the `/derivatives` folder. Please rename your `.nii.gz` files if required before performing the next step.

## Converting scans from NIfTI to MINC

Once renaming is completed, please run the following code in the Terminal window:

```sh
cd /scratch/st-toddwood-1/$USER/dicom2nifti2minc
git pull

PARTICIPANTS_FILE="./data/participants.tsv"
SUB_SIZE=1  # Subjects per job

# Read subject IDs from file (ignore header)
mapfile -t SUBJECTS < <(tail -n +2 "$PARTICIPANTS_FILE" | cut -f1 | tr -d '\r' | sed '/^$/d')

N_SUBJECTS=${#SUBJECTS[@]}
ARRAY_LENGTH=$(( (N_SUBJECTS + SUB_SIZE - 1) / SUB_SIZE ))

echo "Found $N_SUBJECTS subjects. Launching array with $ARRAY_LENGTH jobs."

sbatch --array=0-$((ARRAY_LENGTH - 1)) ./code/nifti2minc.sh
```

Once complete, each subjects' `.mnc` files will be found in the `/derivatives` folder.
