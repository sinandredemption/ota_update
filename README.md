# OTA Update Scripts for Raspberry Pi
A collection of scripts that enable reliable OTA updates for Raspberry Pi based on "Dual Copy" strategy.

**WARNING:** The scripts do not currently support signed updates. As such, please do not use these scripts in a production environment. Please use these scripts for educational purposes only.

## Overview
These scripts are capable of automatically updating the root filesystem of a Raspberry Pi. The update is applied through a update file, which is a system image of the root partition that will replace the current root.

### Dual-Copy
The dual-copy update strategy involves two root partitions where one is active while the other remains inactive. The update image is installed on the inactive partition, and once the update is complete, the boot configuration is modified to use the updated partition as the root partition on the next boot. Therefore, both the partitions switch places as "active" and "inactive" after each update. If, for any reason, the update fails (e.g. due to a power supply cut), the boot configuration remains unchanged, preventing bricking of the device.

## Getting Started

### Prequisites
Make sure the partitioning structure on the Raspberry Pi is as follows:

- **First root filesystem:** `/dev/mmcblk0p2`. Mounted as root on a fresh install of Raspberry Pi OS.
- **Second root filesystem:** `/dev/mmcblk0p3`. Must be exactly the same size as `/dev/mmcblk0p2`.
- **Persistent data:** `/dev/mmcblk0p4`. Automatically mounted to `/mnt/data`. Use it to store persistent data that doesn't change between updates.

#### Dependencies
- `pbzip2` for compression.
- `jq` to parse JSON.
Install using apt-get: `sudo apt-get install -y pbzip2 jq`

### Installation
- Create a folder in root called `update`:

```
$ sudo mkdir /update
```
- Download and copy all the scripts to `/update`:

```
$ ls /update
apply_update.sh  current  latest  ota_service.sh  ota_update.service
```
- Enable the service for OTA Updates:

```
$ sudo cp /update/ota_update.service /etc/systemd/system
$ sudo systemctl enable --now ota_update.service
```

- *Alternatively*, run the OTA update script manually when needed:

```
$ sudo bash /update/ota_service.sh
```

## Usage
The versioning of updates is controlled through two files:

- `/update/current`: Contains the version of the current file, formatted as JSON. Example:

```
{
	version: "1.0"
}
```

- `/update/latest`: Contains the metadata for the latest update, including an optional SHA-256 checksum.

```
{
	version: "1.1",
	url: "http://example.com/update.img.bz2",
	checksum: "sha256 checksum goes here"
}
```

These two files are constantly monitored by the scripts, and as soon as there is a mismatch in versions between by `/update/current` and `/update/latest`, the scripts download the update from the URL pointed by `/update/latest` and apply it.

### Creating a new update image
A update can be created through extracting the filesystem of an already updated device, and then compressed to be sent to other devices over-the-air. Before creating an update, it is important to check if all the OTA Update scripts are themselves installed along with the dependencies, so that the device may recieve further OTA Updates.

The `create_update.sh` script is provided to simplify the process of creating OTA updates. This script performs pre-update checks on the root filesystem, extracts and compresses the root partition image, and saves it to the specified path.

**Usage:** Run the `create_update.sh` script with root privileges.

```
sudo bash create_update.sh /dev/sdXN /path/to/update
```

Replace `/dev/sdXN` with the partition of the root filesystem on your block device, and `/path/to/update` with the desired path for the update image file.

**NOTE:** The script would automatically add `.img.bz2` extension at the end of filename, so there is no need to provide them manually.

#### Creating an update image manually
The `create_update.sh` script can handle the process of creating OTA updates, so manual creation of update images is not required in most cases. The following steps are provided for documentation purposes and may be useful in situations where manual creation is necessary.

##### Pre-update Check
Boot into the Raspberry Pi, and check the following:

- All the dependencies of this project are installed.
- The update scripts are installed in `/update`, and running.
- Files `/update/latest` and `/update/current` point to the same version.

##### Creating an update image
Remove the SD Card from the Raspberry Pi and follow these steps:

- Extract the root partition of the updated filesystem in `.img` format using a tool like `dd`.
- Compress the extracted root partition image to `.bz2` using a program like `pbzip2`. Your update file should now have a name like `<update name>.img.bz2`.

The update file is now ready to be installed. Upload this update file to a server so that it has a URL and can be downloaded through `curl`.

**NOTE:** It is possible to use compression formats apart from `bz2`, but that would involve (only) some tinkering with `apply_update.sh`.

### Signalling an update
The bash script `ota_service.sh` regularly monitors `/update/latest` for changes, so singalling an update is as simple as updating `/update/latest`. Simply change the file `/update/latest`  on the remote device (Raspberry Pi) to reflect the version, URL, and (optionally) SHA-256 checksum of the new update.

**NOTE:** Although optional, it is **highly** recommended to provide the checksum of the update file, to ensure the integrity of the downloaded update (and hence avoid bricking). Please do not skip providing checksum of the update outside of testing purposes, or you **will** eventually brick your device.

### Logs
All of the output of the scripts is redirected to `/var/log/ota_update.log`.

## Scripting Overview
High-level, informal overview of how each script works (straight out of personal notes).

### Update Service | `ota_service.sh`
- Compare file `latest` for changes against `current` every N seconds
- In case a different version is available, call the update script `apply_update.sh` with the URL and (optionally) checksum, and wait for it to return.
- If the update was sucessfull, reboot the system. Otherwise, continue polling.

### Update Script  | `apply_update.sh`
- Download the update from the URL given as the first argument.
- If the checksum is provided as the second argument, verify it corresponds to the downloaded update.
- Find which partition is currently mounted as root, and which partition is inactive.
- Start writing the update image to the inactive partition.
- Once the update image is written to the partition, temporarily mount the updated partition.
- Update the `/etc/fstab` file in the updated partition to specify that it should be mounted as the root partition.
- Update the `cmdline.txt` file to indicate that the system should boot from the updated partition.
- The update has been applied, and the system needs to restart

### Update Creator Script | `create_update.sh`

- Confirm all the dependencies are installed in the root
- Confirm the update scripts themselves are present.
- Confirm if `latest` and `current` are present and equal.
- Create an image of the root file using `dd`.

## Contributing
This project aims to be very hackable. Please feel free to fork or contribute as you please. Here are a some ideas to get started:

- **Support for signed updates:** Adding support for signed updates would render the project suitable for use in a production environment. This feature can be easily implemented by including an extra step to decrypt the update.
- **Ability to update any file of choice:** This feature would be instrumental for updating anything outside of the root partition (for example, files in `/boot` or the persistent data partition). There are several possible implementations for this feature, such as packing the update image together with the files to be updated as a tar archive. However, a crucial consideration would be the ability to support rollback and backup functionalities.
- **Support for rollback:** Adding this feature would allow the Raspberry Pi to go back to booting from the older partition if signalled. This would enable the user to return to the previous, working partition without having to push a new system image update, which would come handy in a situation where something wrong is detected with the new update. Implementating this feature can be achieved by editing `/boot/cmdline.txt`. However, there are various ways of signaling a rollback, which can be explored to determine the best approach.

## Relevant Links
- [SWUpdate](https://sbabic.github.io/swupdate/swupdate.html): Similar software with support for both single-copy and dual-copy approach.
- [System Update - Yocto](https://wiki.yoctoproject.org/wiki/System_Update): A technical comparision of different system update strategies.
- [Updating Embedded System Linux Devices: Update Strategies](https://mkrak.org/2018/01/10/updating-embedded-linux-devices-part1/): Contains very clear explanations of the different update strategies for embedded devices.
