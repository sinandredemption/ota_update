# Script that creates system image updates with sanity checks
function report_error {
    echo "ERROR: $1. Exiting."
    exit 1
}

if [[ "$1" = "" || "$2" = "" ]]; then
    echo "Need two arguments (in order): (1) partition of block device and (2) output name without extensions"
    echo "e.g. bash create_update.sh /dev/sdXN /path/to/update"
    report_error "Not enough arguments"
fi

# Mount partition to a temporary location
tmprootfs="/tmp/rasp_rootfs"
mkdir -p "$tmprootfs"

echo "Mounting $1 to $tmprootfs..."
umount "$1"
mount "$1" "$tmprootfs" || report_error "Couldn't mount $1 to $tmprootfs"

# Check if all dependecies are installed
dependencies=("/usr/bin/pbzip2" "/usr/bin/jq" "/usr/bin/sha256sum" "/usr/bin/dd" "/usr/bin/curl" "/usr/bin/sed" "/update/current" "/update/apply_update.sh" "/update/ota_service.sh" "/etc/systemd/system/multi-user.target.wants/ota_update.service")

# Loop through the array and check if each file exists
for file in "${dependencies[@]}"
do
    echo "Checking for $file..."

    stat "${tmprootfs}${file}" > /dev/null || report_error "Does the file $file exist? Couldn't stat '$file'"

done

rm "$tmprootfs/update/latest" > /dev/null 2>&1

echo "Starting extraction of image from $1 to $2.img.bz2..."
sleep 5

dd if="$1" of="$2.img" bs=4M status=progress || report_error "Failed to create image"
pbzip2 -f -z "$2.img" || report_error "Failed to compress image"

echo "Update image created successfully at '$2.img.bz2'"
