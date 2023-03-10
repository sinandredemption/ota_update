#!/bin/bash

function print_line {
    echo "[$(date +'%b %d %T') ota_update.sh]: $1"
}

mkdir -p /mnt/data

if [[ -z $(lsblk | grep "/mnt/data") ]]; then
    mount /dev/mmcblk0p4 /mnt/data || print_line "WARNING: Couldn't mount /dev/mmcblk0p4 to /mnt/data"
fi

print_line "Monitoring /update/latest for updates."
while :
do
    latest_version=$(cat /update/latest | jq -r '.version')

    if [[ -z "$latest_version" ]]; then
        print_line "No version found. Waiting..."
    # If /update/latest version is different from current version
    elif [[ "$latest_version" != $(cat /update/current | jq -r '.version') ]]; then

        url=$(cat /update/latest | jq -r '.url')
        print_line "Found new version: $latest_version at url '$url'"

        # If checksum is not given in the metadata
        if [[ -z $(cat /update/latest | grep 'checksum') ]]; then

            print_line "Calling apply_update.sh without checksum..."
            # Call update script (pass URL only) and then reboot
            bash /update/apply_update.sh "$url" && reboot || print_line "ERROR: Update failed"

        else

            print_line "Calling apply_update.sh with checksum..."
            # Call update script (pass URL and checksum) and then reboot
            bash /update/apply_update.sh "$url" $(cat /update/latest | jq -r '.checksum') && reboot || print_line "ERROR: Update failed"

        fi
    fi

    sleep 60
done
