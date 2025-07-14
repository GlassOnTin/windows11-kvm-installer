#!/bin/bash

# Enable folder sharing between Linux host and Windows 11 VM
# This script sets up virtio-fs or 9p filesystem sharing

set -e

echo "=== Windows 11 VM Folder Sharing Setup ==="

VM_NAME="Windows11"
SHARE_PATH="/home/ian"
SHARE_TAG="home_share"

# Check if VM exists
if ! virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
    echo "Error: VM '$VM_NAME' not found"
    exit 1
fi

# Check if VM is running
VM_STATE=$(virsh --connect qemu:///session domstate "$VM_NAME")
if [ "$VM_STATE" == "running" ]; then
    echo "VM is currently running. It needs to be shut down to add folder sharing."
    echo "Shut down the VM now? (y/n)"
    read -p "Choice: " shutdown_choice
    if [ "$shutdown_choice" = "y" ]; then
        echo "Shutting down VM..."
        virsh --connect qemu:///session shutdown "$VM_NAME"
        echo "Waiting for VM to shut down..."
        while [ "$(virsh --connect qemu:///session domstate $VM_NAME)" != "shut off" ]; do
            sleep 2
        done
        echo "✓ VM shut down"
    else
        echo "Please shut down the VM manually and run this script again"
        exit 1
    fi
fi

echo ""
echo "Choose sharing method:"
echo "1. virtio-fs (Recommended - Better performance, requires virtiofsd)"
echo "2. 9p filesystem (Legacy - Works everywhere, slower)"
read -p "Choice (1 or 2): " share_method

# Create temporary XML file for device addition
TEMP_XML="/tmp/filesystem_device.xml"

if [ "$share_method" = "1" ]; then
    echo ""
    echo "Setting up virtio-fs sharing..."
    
    # Check if virtiofsd is installed
    if ! command -v virtiofsd &> /dev/null; then
        echo "virtiofsd not found. Installing..."
        sudo apt update
        sudo apt install -y virtiofsd
    fi
    
    # Create virtio-fs device XML
    cat > "$TEMP_XML" << EOF
<filesystem type='mount' accessmode='passthrough'>
  <driver type='virtiofs'/>
  <source dir='$SHARE_PATH'/>
  <target dir='$SHARE_TAG'/>
  <address type='pci'/>
</filesystem>
EOF
    
    echo "Note: virtio-fs requires additional setup:"
    echo "1. A virtiofsd daemon will need to run when the VM starts"
    echo "2. Windows requires WinFsp and VirtIO-FS drivers"
    echo ""
    echo "Download Windows drivers from:"
    echo "- WinFsp: https://github.com/winfsp/winfsp/releases"
    echo "- VirtIO-FS driver: https://github.com/virtio-win/kvm-guest-drivers-windows"
    
else
    echo ""
    echo "Setting up 9p filesystem sharing..."
    
    # Create 9p filesystem device XML
    cat > "$TEMP_XML" << EOF
<filesystem type='mount' accessmode='mapped'>
  <driver type='path' wrpolicy='immediate'/>
  <source dir='$SHARE_PATH'/>
  <target dir='$SHARE_TAG'/>
  <address type='pci'/>
</filesystem>
EOF
    
    echo "Note: 9p sharing requires special Windows drivers"
fi

# Attach the filesystem device to the VM
echo ""
echo "Adding filesystem device to VM..."
virsh --connect qemu:///session attach-device "$VM_NAME" "$TEMP_XML" --config

# Clean up
rm -f "$TEMP_XML"

echo "✓ Filesystem sharing configured"

# Create Windows mount script
WIN_MOUNT_SCRIPT="$HOME/mount-linux-share-windows.txt"
cat > "$WIN_MOUNT_SCRIPT" << 'EOF'
=== Windows Mount Instructions ===

For virtio-fs:
1. Install WinFsp from https://github.com/winfsp/winfsp/releases
2. Install VirtIO-FS driver from virtio-win.iso or download from:
   https://github.com/virtio-win/kvm-guest-drivers-windows
3. After driver installation, the share should appear as a network drive

For 9p filesystem:
1. Download and install the 9p driver for Windows from:
   https://github.com/virtio-win/kvm-guest-drivers-windows
2. Open Device Manager and look for "PCI Device" with missing driver
3. Update driver and point to the downloaded 9p driver
4. Once installed, mount using command prompt as Administrator:
   
   net use Z: \\virtio-fs\home_share
   
   OR for 9p:
   
   net use Z: \\9p\home_share

Alternative mounting (PowerShell as Administrator):
   New-PSDrive -Name Z -PSProvider FileSystem -Root "\\virtio-fs\home_share" -Persist

Troubleshooting:
- If drive doesn't appear, check Device Manager for VirtIO devices
- Ensure all VirtIO drivers are properly installed
- Try restarting the VM after driver installation
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Start the VM: virsh --connect qemu:///session start $VM_NAME"
echo "2. Install required Windows drivers (see $WIN_MOUNT_SCRIPT)"
echo "3. Mount the shared folder in Windows"
echo ""
echo "Shared folder: $SHARE_PATH -> Windows drive"
echo "Instructions saved to: $WIN_MOUNT_SCRIPT"
echo ""

# Additional helper script for virtiofsd
if [ "$share_method" = "1" ]; then
    VIRTIOFSD_SCRIPT="$HOME/start-virtiofsd.sh"
    cat > "$VIRTIOFSD_SCRIPT" << EOF
#!/bin/bash
# Start virtiofsd daemon for folder sharing
# Run this before starting the VM if using virtio-fs

SOCKET_PATH="/tmp/virtiofsd-$VM_NAME.sock"
SHARE_PATH="$SHARE_PATH"

echo "Starting virtiofsd daemon..."
sudo virtiofsd --socket-path="\$SOCKET_PATH" --shared-dir="\$SHARE_PATH" --cache=auto &
echo "✓ virtiofsd started"
echo "Socket: \$SOCKET_PATH"
echo "PID: \$!"
EOF
    chmod +x "$VIRTIOFSD_SCRIPT"
    
    echo "For virtio-fs, you may need to run: $VIRTIOFSD_SCRIPT"
    echo "(This starts the virtiofsd daemon that handles the filesystem sharing)"
fi