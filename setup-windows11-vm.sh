#!/bin/bash

# Windows 11 KVM/QEMU VM Setup Script
# This script automates the installation of KVM/QEMU and sets up a Windows 11 VM

set -e  # Exit on error

echo "=== Windows 11 VM Setup Script ==="

# Step 1: Check if running with sudo and recommend against it
if [ "$EUID" -eq 0 ]; then
    echo "Warning: Running with sudo can cause permission issues."
    echo "Recommended: Run this script without sudo."
    echo ""
    echo "Continue anyway? (y/n)"
    read -p "Choice: " continue_choice
    if [ "$continue_choice" != "y" ]; then
        echo "Exiting. Please run without sudo: ./setup-windows11-vm.sh"
        exit 0
    fi
fi

# Step 2: Check for Windows 11 ISO
ISO_PATH="/media/ian/Ventoy/Win11_24H2_EnglishInternational_x64.iso"
if [ ! -f "$ISO_PATH" ]; then
    echo "Error: Windows 11 ISO not found at $ISO_PATH"
    echo "Please mount your USB drive containing the Windows 11 ISO"
    exit 1
fi
echo "✓ Windows 11 ISO found"

# Step 3: Update system and install KVM/QEMU packages
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

# Step 4: Add current user to necessary groups
ACTUAL_USER=${SUDO_USER:-$USER}
echo "Adding user to kvm and libvirt groups..."
sudo usermod -a -G kvm $ACTUAL_USER
sudo usermod -a -G libvirt $ACTUAL_USER
echo "✓ User added to groups (logout/login required for changes to take effect)"

# Step 5: Start and enable libvirt service
echo "Starting libvirt service..."
sudo systemctl start libvirtd
sudo systemctl enable libvirtd
echo "✓ Libvirt service started"

# Step 6: Create VM directory
# Use the actual user's home directory when run with sudo
REAL_USER=${SUDO_USER:-$USER}
VM_DIR="/home/$REAL_USER/VMs"
VM_NAME="Windows11"
DISK_PATH="$VM_DIR/win11.qcow2"

echo "Creating VM directory..."
mkdir -p "$VM_DIR"
# Ensure proper ownership
chown "$REAL_USER:$REAL_USER" "$VM_DIR"
echo "✓ VM directory created"

# Step 6: Create disk image
echo "Creating 60GB disk image..."
qemu-img create -f qcow2 "$DISK_PATH" 60G
# Ensure proper ownership of the disk image
chown "$REAL_USER:$REAL_USER" "$DISK_PATH"
# Make sure the disk is readable by libvirt-qemu user
chmod 644 "$DISK_PATH"
echo "✓ Disk image created"

# Step 7: Download VirtIO drivers (optional but recommended)
VIRTIO_ISO="$VM_DIR/virtio-win.iso"
if [ ! -f "$VIRTIO_ISO" ]; then
    echo "Downloading VirtIO drivers (optional)..."
    wget --progress=bar:force:noscroll https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso -O "$VIRTIO_ISO" || {
        echo "Warning: Could not download VirtIO drivers. Continuing without them."
        VIRTIO_ISO=""
    }
    # Ensure proper ownership if download succeeded
    if [ -f "$VIRTIO_ISO" ]; then
        chown "$REAL_USER:$REAL_USER" "$VIRTIO_ISO"
    fi
fi

# Step 8: Create Windows 11 VM
echo "Creating Windows 11 VM..."

# Check if VM already exists
VM_CHECK_CMD="virsh --connect qemu:///session list --all"
if [ "$EUID" -eq 0 ]; then
    # Running as root, check as actual user
    VM_EXISTS=$(sudo -u "$REAL_USER" $VM_CHECK_CMD | grep -c "$VM_NAME" || true)
else
    VM_EXISTS=$($VM_CHECK_CMD | grep -c "$VM_NAME" || true)
fi

if [ "$VM_EXISTS" -gt 0 ]; then
    echo "Warning: VM '$VM_NAME' already exists!"
    echo "Options:"
    echo "1. Delete existing VM and create new one"
    echo "2. Exit (keep existing VM)"
    read -p "Choose option (1 or 2): " choice
    
    if [ "$choice" = "1" ]; then
        echo "Deleting existing VM..."
        if [ "$EUID" -eq 0 ]; then
            # Running as root, delete as actual user
            sudo -u "$REAL_USER" virsh --connect qemu:///session destroy "$VM_NAME" 2>/dev/null || true
            sleep 1
            # Remove any managed save state
            sudo -u "$REAL_USER" virsh --connect qemu:///session managedsave-remove "$VM_NAME" 2>/dev/null || true
            # Now undefine the VM
            sudo -u "$REAL_USER" virsh --connect qemu:///session undefine "$VM_NAME" --nvram 2>/dev/null || true
            # Double check and try alternative deletion methods
            if sudo -u "$REAL_USER" virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
                echo "Trying alternative deletion method..."
                sudo -u "$REAL_USER" virsh --connect qemu:///session undefine "$VM_NAME" --remove-all-storage --nvram 2>/dev/null || true
            fi
        else
            virsh --connect qemu:///session destroy "$VM_NAME" 2>/dev/null || true
            sleep 1
            # Remove any managed save state
            virsh --connect qemu:///session managedsave-remove "$VM_NAME" 2>/dev/null || true
            # Now undefine the VM
            virsh --connect qemu:///session undefine "$VM_NAME" --nvram 2>/dev/null || true
            # Double check and try alternative deletion methods
            if virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
                echo "Trying alternative deletion method..."
                virsh --connect qemu:///session undefine "$VM_NAME" --remove-all-storage --nvram 2>/dev/null || true
            fi
        fi
        
        # Verify deletion
        if [ "$EUID" -eq 0 ]; then
            VM_STILL_EXISTS=$(sudo -u "$REAL_USER" virsh --connect qemu:///session list --all | grep -c "$VM_NAME" || true)
        else
            VM_STILL_EXISTS=$(virsh --connect qemu:///session list --all | grep -c "$VM_NAME" || true)
        fi
        
        if [ "$VM_STILL_EXISTS" -gt 0 ]; then
            echo "Error: Failed to delete VM. Please delete manually with:"
            echo "virsh --connect qemu:///session undefine $VM_NAME --nvram"
            exit 1
        fi
        
        # Also delete the disk file to start fresh
        if [ -f "$DISK_PATH" ]; then
            rm -f "$DISK_PATH"
            echo "Deleted existing disk file"
        fi
        
        echo "✓ Existing VM deleted"
    else
        echo "Keeping existing VM. Exiting..."
        exit 0
    fi
fi

echo "Note: Using SATA disk interface to ensure Windows can see the disk"

# Build the virt-install command
# Note: Using existing disk instead of letting virt-install create it to avoid permission issues
VIRT_INSTALL_CMD="virt-install \
    --connect qemu:///session \
    --name=$VM_NAME \
    --os-variant=win11 \
    --ram=8192 \
    --vcpus=4 \
    --cpu host-passthrough \
    --disk path=$DISK_PATH,bus=sata,format=qcow2 \
    --cdrom=$ISO_PATH \
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
    VIRT_INSTALL_CMD="$VIRT_INSTALL_CMD --disk $VIRTIO_ISO,device=cdrom,bus=sata"
fi

# Execute the command as the actual user
if [ "$EUID" -eq 0 ]; then
    # Running as root, switch to actual user
    sudo -u "$REAL_USER" bash -c "$VIRT_INSTALL_CMD"
else
    # Running as regular user
    bash -c "$VIRT_INSTALL_CMD"
fi

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
