#!/bin/bash

# Setup virtio-fs folder sharing for Windows 11 VM
# This script configures virtio-fs with proper socket handling

set -e

echo "=== VirtIO-FS Setup for Windows 11 VM ==="

VM_NAME="Windows11"
SHARE_PATH="/home/ian"
SHARE_TAG="share0"
SOCKET_PATH="/tmp/virtiofs-${VM_NAME}.sock"

# Check if VM exists
if ! virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
    echo "Error: VM '$VM_NAME' not found"
    exit 1
fi

# Check if virtiofsd is installed
if ! command -v /usr/libexec/virtiofsd &> /dev/null && ! command -v virtiofsd &> /dev/null; then
    echo "virtiofsd not found. Installing..."
    sudo apt update
    sudo apt install -y virtiofsd
fi

# Find virtiofsd path
if [ -x "/usr/libexec/virtiofsd" ]; then
    VIRTIOFSD_BIN="/usr/libexec/virtiofsd"
elif command -v virtiofsd &> /dev/null; then
    VIRTIOFSD_BIN=$(which virtiofsd)
else
    echo "Error: virtiofsd not found after installation"
    exit 1
fi

echo "Found virtiofsd at: $VIRTIOFSD_BIN"

# Check if VM is running
VM_STATE=$(virsh --connect qemu:///session domstate "$VM_NAME")
if [ "$VM_STATE" == "running" ]; then
    echo ""
    echo "VM must be shut down to add virtio-fs device."
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

# Create systemd user service for virtiofsd
echo ""
echo "Creating systemd user service for virtiofsd..."
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/virtiofsd-windows11.service << EOF
[Unit]
Description=VirtIO-FS daemon for Windows11 VM
Before=libvirtd.service

[Service]
Type=simple
ExecStart=$VIRTIOFSD_BIN \
    --socket-path=$SOCKET_PATH \
    --shared-dir=$SHARE_PATH \
    --cache=auto \
    --announce-submounts
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Reload systemd and start the service
systemctl --user daemon-reload
systemctl --user enable virtiofsd-windows11.service
systemctl --user start virtiofsd-windows11.service

# Wait for socket to be created
echo "Waiting for virtiofsd to start..."
sleep 2

# Check if service is running
if ! systemctl --user is-active virtiofsd-windows11.service >/dev/null; then
    echo "Error: virtiofsd service failed to start"
    echo "Check logs with: journalctl --user -u virtiofsd-windows11"
    exit 1
fi

echo "✓ virtiofsd service started"

# Create filesystem device XML
TEMP_XML="/tmp/virtiofs_device.xml"
cat > "$TEMP_XML" << EOF
<filesystem type='mount' accessmode='passthrough'>
  <driver type='virtiofs' queue='1024'/>
  <source socket='$SOCKET_PATH'/>
  <target dir='$SHARE_TAG'/>
  <address type='pci'/>
</filesystem>
EOF

# Add the filesystem device to VM
echo ""
echo "Adding virtio-fs device to VM..."
virsh --connect qemu:///session attach-device "$VM_NAME" "$TEMP_XML" --config --persistent

# Clean up
rm -f "$TEMP_XML"

echo "✓ VirtIO-FS device added to VM"

# Create Windows instructions
WIN_INSTRUCTIONS="$HOME/virtiofs-windows-setup.txt"
cat > "$WIN_INSTRUCTIONS" << 'EOF'
=== Windows VirtIO-FS Setup Instructions ===

The VirtIO-FS share is now configured on the Linux side.

In Windows:

1. Start the VM:
   virsh --connect qemu:///session start Windows11

2. Once Windows boots, the VirtIO-FS device should be recognized
   if the drivers are properly installed.

3. Open "This PC" or File Explorer
   - You should see a new drive automatically mounted
   - If not, continue with manual steps below

4. Manual mounting (if needed):
   Open PowerShell as Administrator and run:

   # Check if WinFsp service is running
   Get-Service WinFsp.Launcher

   # If not running, start it:
   Start-Service WinFsp.Launcher

   # The drive should appear automatically after this

5. If the drive still doesn't appear:
   - Open Device Manager
   - Look for "VirtIO FS Device" under Storage controllers
   - If there's a yellow exclamation mark, update the driver
   - Point to the VirtIO drivers you installed

6. Alternative manual mount (PowerShell as Admin):
   # Create a mount point
   New-Item -ItemType Directory -Force -Path C:\LinuxHome
   
   # Mount using WinFsp
   & "C:\Program Files (x86)\WinFsp\bin\launchctl-x64.exe" start virtiofs share0 C:\LinuxHome

Troubleshooting:
- Ensure WinFsp is installed (required for VirtIO-FS on Windows)
- Check Event Viewer → Windows Logs → System for any errors
- Verify VirtIO-FS driver is properly installed in Device Manager
- The share tag is "share0" if you need to reference it

The shared folder contains: /home/ian (your Linux home directory)
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "VirtIO-FS is now configured with:"
echo "- Shared directory: $SHARE_PATH"
echo "- Socket path: $SOCKET_PATH"
echo "- Share tag: $SHARE_TAG"
echo ""
echo "The virtiofsd daemon is running as a systemd user service."
echo "It will start automatically when you log in."
echo ""
echo "To manage the service:"
echo "- Status: systemctl --user status virtiofsd-windows11"
echo "- Logs: journalctl --user -u virtiofsd-windows11"
echo "- Restart: systemctl --user restart virtiofsd-windows11"
echo ""
echo "Next steps:"
echo "1. Start the VM: virsh --connect qemu:///session start Windows11"
echo "2. The shared folder should appear as a drive in Windows"
echo ""
echo "Windows instructions saved to: $WIN_INSTRUCTIONS"