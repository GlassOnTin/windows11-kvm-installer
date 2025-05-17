# Windows 11 KVM/QEMU VM Setup

This repository contains scripts and documentation for setting up Windows 11 virtual machines using KVM/QEMU on Ubuntu/Debian systems.

## Prerequisites

- Ubuntu/Debian-based Linux system
- Hardware virtualization support (Intel VT-x or AMD-V)
- Windows 11 ISO file
- Minimum 8GB RAM (16GB+ recommended)
- At least 60GB free disk space

## Quick Start

1. Mount your USB drive containing the Windows 11 ISO:
   ```bash
   sudo mount /dev/sdb1 /mnt/usb
   ```

2. Run the setup script:
   ```bash
   bash setup-windows11-vm.sh
   ```

3. Connect to the VM:
   ```bash
   virt-viewer --connect qemu:///session Windows11
   ```

## What the Script Does

1. **Checks for Windows 11 ISO**: Verifies the ISO is available at the expected location
2. **Installs KVM/QEMU packages**: Installs all necessary virtualization software
3. **Configures user permissions**: Adds your user to kvm and libvirt groups
4. **Creates VM infrastructure**: Sets up directories and disk images
5. **Creates the VM**: Launches a Windows 11 VM with appropriate settings

## VM Specifications

- **Name**: Windows11
- **RAM**: 8GB
- **CPUs**: 4 cores
- **Disk**: 60GB (SATA interface for compatibility)
- **Network**: User mode networking
- **Graphics**: VNC
- **Firmware**: UEFI
- **Machine Type**: Q35

## Important Notes

### Disk Interface
The VM uses SATA disk interface instead of VirtIO for better Windows compatibility. This means:
- Windows will detect the disk during installation without additional drivers
- Performance may be slightly lower than VirtIO
- You can add VirtIO drivers later for better performance

### Group Membership
After running the script, you need to log out and log back in for group membership changes to take effect.

### VM Management

List all VMs:
```bash
virsh --connect qemu:///session list --all
```

Start VM:
```bash
virsh --connect qemu:///session start Windows11
```

Stop VM:
```bash
virsh --connect qemu:///session shutdown Windows11
```

Force stop VM:
```bash
virsh --connect qemu:///session destroy Windows11
```

Delete VM:
```bash
virsh --connect qemu:///session undefine Windows11 --nvram
```

## Troubleshooting

### Cannot Connect to VM
- Ensure the VM is running: `virsh --connect qemu:///session list`
- Check VNC display: `virsh --connect qemu:///session vncdisplay Windows11`

### Disk Not Visible During Installation
- The script uses SATA interface which should be compatible
- If issues persist, you may need to load storage drivers during Windows setup

### Permission Denied Errors
- Ensure you've logged out and back in after group changes
- Check group membership: `groups | grep -E 'kvm|libvirt'`

## Advanced Configuration

### Using VirtIO Drivers
For better performance, you can add VirtIO drivers:
1. Download virtio-win.iso from Fedora
2. Attach as secondary CD during installation
3. Load drivers during Windows setup

### Network Configuration
The default setup uses user-mode networking. For bridged networking:
1. Create a bridge interface
2. Modify the virt-install command to use `--network bridge=br0`

### TPM Support
TPM is not configured in this basic setup. For TPM support:
1. Install swtpm packages
2. Add TPM configuration to virt-install command

## Contributing

Feel free to submit issues or pull requests to improve this setup process.

## License

This project is provided as-is for educational and personal use.