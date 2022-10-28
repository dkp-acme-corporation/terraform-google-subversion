<!--BOF-->
# RedHat Ansible Roles

### Ansible Configuration

The Ansible Configuration job runs ansible to install Terraform Enterprise. The `playbook.yml` runs the following roles:

1. [setupDisk](./roles/setupDisk/):  Partitions and adds disks (data and application) to the LVM groups

<!--EOF-->