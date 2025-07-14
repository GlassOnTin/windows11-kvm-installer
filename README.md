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

### Basic Operations

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

### Management Script
Use the included management script for easy VM control:
```bash
./manage-vm.sh
```

## Folder Sharing

Share your Linux home folder with the Windows VM using one of these methods:

### Method 1: VirtIO-FS (Recommended - Best Performance)
**Prerequisites**: Install VirtIO-FS drivers in Windows first

```bash
./setup-virtiofs.sh
```

This creates a high-performance shared folder using VirtIO-FS:
- Automatically starts virtiofsd daemon via systemd
- Your /home/ian folder appears as a drive in Windows
- Best performance for file operations

### Method 2: SMB Sharing (Easiest - No Drivers Needed)
```bash
./enable-smb-sharing.sh
```

Access from Windows:
- Open File Explorer
- Type `\\10.0.2.4\qemu` in the address bar
- Your Linux home folder is accessible immediately

### Method 3: 9P Filesystem (Legacy)
```bash
./enable-folder-sharing.sh
```

Choose option 2 for 9P filesystem sharing. Requires special Windows drivers.

## USB Device Support

Enable USB passthrough to use USB devices in the VM:
```bash
./add-usb-support.sh
```

This converts the VM to use SPICE graphics and enables USB redirection.

## Troubleshooting

### Cannot Connect to VM
- Ensure the VM is running: `virsh --connect qemu:///session list`
- Check VNC display: `virsh --connect qemu:///session vncdisplay Windows11`

### Disk Not Visible During Installation
**This is the most common issue!** Here's how to fix it:

1. **Check disk configuration**: The script uses SATA interface by default, which Windows should recognize
2. **Verify disk exists**: Run `virsh --connect qemu:///session domblklist Windows11`
3. **During Windows setup**: 
   - If no disk is visible, click "Load driver"
   - If VirtIO drivers were downloaded, browse to the secondary CD drive (usually D:)
   - Look for the appropriate driver folder (e.g., `viostor\w11\amd64`)
   - Select the driver and continue
4. **Alternative approaches**:
   - Use IDE instead of SATA: Edit the script to use `bus=ide`
   - Pre-format the disk: Use `qemu-img create -f qcow2 -o preallocation=full`
   - Check UEFI settings in the VM for disk controller options

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