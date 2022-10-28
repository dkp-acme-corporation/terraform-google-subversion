# setupDisk Ansible Role
## TOC
- [Overview](#overview)
- [License](#license)
- [Contact](#contact)

<!-- ABOUT THE PROJECT -->
## Overview
The setupDisk role gathers information about disk and partitions then partitions and adds disks (data and application) to the LVM groups as necessary. The current role only applies to the development environment as the infrastructure is spun up dynamically via Terraform. The role is skipped for production as the VMs are delivered according to the spec in the SIA.

### Defaults
| Variable Name | Description |  Default |
|---|---|---|
| rvStandardOsDeviceExcludeRegex | Regular expression syntax for Devices to exclude |  `^sda` |
| rvStandardOsDiskExcludeRegex | Regular expression syntax for Disks to exclude  |  `^/dev/sda` |
| rvDefaultVolumeGroupNamePrefix | Default volume group name prefix  |  `vg` |
| rvDefaultVolumeGroupStartNumber | Starting number for the volume groups  |  `1` |
| rvDefaultVolumeGroupPeSize | pe size of the volume group  |  `4096` |
| rvDefaultLogicalVolumeNamePrefixData | Prefix to be used for the data logical volume |  `dat` |
| rvDefaultLogicalVolumeNamePrefixApp | Prefix to be used for the application logical volume |  `app` |
| rvDefaultLogicalVolumeRootDirectory | Root Directory for the logical volume |  `/opt` |
| rvDefaultLogicalVolumeFileSystemType | disk type for the logical volume |  `xfs` |
| rvDefaultFileSystemMountDataName | Mount name for the data disk |  `data` |
| rvDefaultFileSystemMountDataUnderAppInstance | Location to start the data disk |  `1` |
| rvDefaultDiskPartitionNumber | Partition Number of the default disk |  `1` |

### Tasks
- main.yml: Tasks to complete the disk setup.

<!-- LICENSE -->
## License

<!-- CONTACT -->

## Contact
