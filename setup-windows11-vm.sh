#!/bin/bash

# Windows 11 KVM/QEMU VM Setup Script
# This script automates the installation of KVM/QEMU and sets up a Windows 11 VM

set -e  # Exit on error

echo "=== Windows 11 VM Setup Script ==="

# Step 1: Check for Windows 11 ISO
ISO_PATH="/mnt/usb/Win11_24H2_EnglishInternational_x64.iso"
if [ ! -f "$ISO_PATH" ]; then
    echo "Error: Windows 11 ISO not found at $ISO_PATH"
    echo "Please mount your USB drive containing the Windows 11 ISO"
    exit 1
fi
echo "✓ Windows 11 ISO found"

# Step 2: Update system and install KVM/QEMU packages
echo "Installing KVM/QEMU packages..."
sudo apt update
sudo apt install -y \
    qemu-kvm \
    qemu-system-x86 \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    virt-manager \
    ovmf \
    virt-viewer \
    swtpm \
    swtpm-tools

echo "✓ KVM/QEMU packages installed"

# Step 3: Add current user to necessary groups
echo "Adding user to kvm and libvirt groups..."
sudo usermod -a -G kvm $USER
sudo usermod -a -G libvirt $USER
echo "✓ User added to groups (logout/login required for changes to take effect)"

# Step 4: Start and enable libvirt service
echo "Starting libvirt service..."
sudo systemctl start libvirtd
sudo systemctl enable libvirtd
echo "✓ Libvirt service started"

# Step 5: Create VM directory
VM_DIR="$HOME/VMs"
VM_NAME="Windows11"
DISK_PATH="$VM_DIR/win11.qcow2"

echo "Creating VM directory..."
mkdir -p "$VM_DIR"
echo "✓ VM directory created"

# Step 6: Create disk image
echo "Creating 60GB disk image..."
qemu-img create -f qcow2 "$DISK_PATH" 60G
echo "✓ Disk image created"

# Step 7: Download VirtIO drivers (optional but recommended)
VIRTIO_ISO="$VM_DIR/virtio-win.iso"
if [ ! -f "$VIRTIO_ISO" ]; then
    echo "Downloading VirtIO drivers (optional)..."
    wget -q https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso -O "$VIRTIO_ISO" || {
        echo "Warning: Could not download VirtIO drivers. Continuing without them."
        VIRTIO_ISO=""
    }
fi

# Step 8: Create Windows 11 VM
echo "Creating Windows 11 VM..."
echo "Note: Using SATA disk interface to ensure Windows can see the disk"

# Build the virt-install command
VIRT_INSTALL_CMD="virt-install \
    --connect qemu:///session \
    --name=\"$VM_NAME\" \
    --os-variant=win11 \
    --ram=8192 \
    --vcpus=4 \
    --cpu host-passthrough \
    --disk path=\"$DISK_PATH\",size=60,bus=sata,format=qcow2 \
    --cdrom=\"$ISO_PATH\" \
    --network user \
    --graphics vnc \
    --video qxl \
    --machine q35 \
    --boot uefi \
    --check all=off \
    --noautoconsole"

# Add VirtIO drivers ISO if available
if [ -n "$VIRTIO_ISO" ] && [ -f "$VIRTIO_ISO" ]; then
    echo "VirtIO drivers available - adding as secondary CD"
    VIRT_INSTALL_CMD="$VIRT_INSTALL_CMD --disk \"$VIRTIO_ISO\",device=cdrom,bus=sata"
fi

# Execute the command
eval $VIRT_INSTALL_CMD

echo "✓ VM created and started"

# Step 9: Display connection information
echo ""
echo "=== VM Setup Complete ==="
echo ""
echo "Windows 11 VM is now running. You can connect to it using:"
echo "1. virt-viewer: virt-viewer --connect qemu:///session $VM_NAME"
echo "2. VNC client: Connect to localhost:5900 (or 127.0.0.1:5900)"
echo "3. virt-manager: Launch virt-manager for GUI management"
echo ""
echo "=== IMPORTANT: Disk Visibility During Installation ==="
echo "The VM uses SATA disk interface which Windows should recognize."
echo "If NO DISK is visible during Windows installation:"
echo "1. The disk should appear automatically with SATA interface"
echo "2. If VirtIO drivers were downloaded, they're on the D: drive"
echo "3. You may need to click 'Load driver' and browse to D:\\"
echo ""
echo "VM Management commands:"
echo "- List VMs: virsh --connect qemu:///session list --all"
echo "- Stop VM: virsh --connect qemu:///session shutdown $VM_NAME"
echo "- Start VM: virsh --connect qemu:///session start $VM_NAME"
echo "- Delete VM: virsh --connect qemu:///session undefine $VM_NAME --nvram"
echo "- Check VM disks: virsh --connect qemu:///session domblklist $VM_NAME"