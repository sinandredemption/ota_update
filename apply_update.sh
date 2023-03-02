#!/bin/bash
# -- Helper Functions --
function print_line {
    line="[$(date +'%b %d %T') ota_update.sh]: $1"
    echo "$line" >> /var/log/ota_update.log
    echo "$line"
}

function report_error {
    print_line "ERROR: $1. Exiting."
    exit 1
}

# -- Globals --
update_mount_path="/mnt/rootfs" # Path where the updated root will temporarily be mounted
data_mount_path="/mnt/data"
update_file="$data_mount_path/rootfs.img.bz2"

# -- Main Script --

# Perform some sanity checks first
print_line "Checking if script is running as root..."

if [[ "$EUID" -ne 0 ]]; then
    report_error "Please run this script as root"
fi

# Check if data mount path is actually mounted to something
if [[ -z $(lsblk | grep "$data_mount_path") ]]; then
    report_error "Nothing mounted to $data_mount_path"
fi

print_line "Downloading the update from '$1'..."
# Download the update image file
curl $1 --output "$update_file" || report_error "Downloading '$1' failed"

if [ ! -f "$update_file" ]; then
    report_error "Couldn't download to file $update_file"
fi

# Check if a checksum is provided
if [ -z "$2" ]; then
    print_line "No checksum provided. This is a security risk."
else
    print_line "Verifying SHA-256 checksum..."

    sha256=$(sha256sum "$update_file" | awk '{print $1}')
    if [[ "$sha256" != "$2" ]]; then
        print_line "EXPECT: $2"
        print_line "ACTUAL: $sha256"
        report_error "SHA-256 checksums do not match"
    else
        print_line "Verification successful"
    fi
fi

active_partition_uuid=$(grep -o 'root=[^ ]*' /boot/cmdline.txt)
active_partition_uuid=${active_partition_uuid:5} # Ignore 'root=' in the beginning

active_partition_suffix=$(echo $active_partition_uuid | grep -o '.\{3\}$')

case $active_partition_suffix in
    "-03")
        update_partition="/dev/mmcblk0p2"
        update_partition_suffix="-02"
        ;;
    "-02")
        update_partition="/dev/mmcblk0p3"
        update_partition_suffix="-03"
        ;;
    *)
        report_error "Unknown active partition $active_partition_uuid"
        ;;
esac

update_partition_uuid=$(echo $active_partition_uuid | sed "s/$active_partition_suffix/$update_partition_suffix/")

print_line "active partition uuid=$active_partition_uuid suffix=$active_partition_suffix"
print_line "update partition uuid=$update_partition_uuid suffix=$update_partition_suffix"
print_line "The update will be installed on $update_partition"

if [[ -z $update_partition || -z $update_partition_suffix ]]; then
    print_line "ERROR: Please check if two ext4 partitions (/dev/mmcblk0p2 and /dev/mmcblk0p3) of equal size are present"
    report_error "Can't detect active and update partition"
fi

print_line "Starting in 5 secs..."
sleep 5

compression_type=${update_file##*.}

if [[ "$compression_type" != 'bz2' ]]; then
    report_error "Image file $update_file is not compressed with bz2"
fi

# Get the name of uncompressed image file
img=${update_file%.img*}.img

print_line "Extracting $update_file to $img..."

# Extract using pbzip2 (uses multiple threads)
pbzip2 -f --verbose -d $update_file || report_error "Extraction failed."

# Confirm that the raw-image file is present
stat $img > /dev/null 2>&1 || report_error "Expected file '$img' not found"

print_line "Updating partition $update_partition..."

# Unmount the update partition. Not neccessary, but just in case...
umount $update_partition > /dev/null 2>&1

# Apply update
dd if=$img of=$update_partition bs=4M status=progress || report_error "Updating failed"

print_line "Mounting $update_partition to $update_mount_path"
mkdir -p $update_mount_path || report_error "Couldn't create path $update_mount_path for mounting"
mount $update_partition $update_mount_path || report_error "Couldn't mount $update_partition to $update_mount_path"

# Edit the fstab of the new root so that it mounts the update partition to root
print_line "Editing /etc/fstab of the updated image"

cp /etc/fstab "$update_mount_path/etc/fstab" || report_error "Couldn't update /etc/fstab of the new root partition"

# Find the line that mounts the currently active partition to root
current_root=$(grep -E '^\S+\s+\/\s+' "$update_mount_path/etc/fstab" | grep -v '^#')
# Replace it so that the updated partition is mounted to root
sed -i "/^$active_partition_uuid/d" "$update_mount_path/etc/fstab" || report_error "Couldn't modify /etc/fstab of the new root partition"
echo $current_root | sed "s/$active_partition_suffix/$update_partition_suffix/" >> "$update_mount_path/etc/fstab" || report_error "Couldn't write to the /etc/fstab of the new root partition"

print_line "Updating cmdline.txt (backup = /boot/cmdline.txt.bak)..."

# Create a backup of kernel parameters
cp /boot/cmdline.txt /boot/cmdline.txt.bak || report_error "Couldn't backup /boot/cmdline.txt"
# Configure the kernel parameters to consider the updated partition as root
sed -i "s/$active_partition_uuid/$update_partition_uuid/" /boot/cmdline.txt || report_error "Couldn't update /boot/cmdline.txt"

print_line "Update applied successfully"
