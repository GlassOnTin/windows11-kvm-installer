#!/bin/bash

# Script to troubleshoot and fix disk visibility issues in Windows 11 VM

VM_NAME="Windows11"
VM_DIR="$HOME/VMs"

echo "=== Windows 11 VM Disk Troubleshooting ==="
echo ""

# Check if VM exists
if ! virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
    echo "Error: VM '$VM_NAME' not found"
    exit 1
fi

# Show current disk configuration
echo "1. Current disk configuration:"
virsh --connect qemu:///session domblklist "$VM_NAME"
echo ""

# Show disk details
echo "2. Disk details:"
virsh --connect qemu:///session dumpxml "$VM_NAME" | grep -A 10 "disk.*device='disk'"
echo ""

# Check disk file
DISK_PATH="$VM_DIR/win11.qcow2"
echo "3. Disk file check:"
if [ -f "$DISK_PATH" ]; then
    echo "Disk file exists: $DISK_PATH"
    ls -lh "$DISK_PATH"
    qemu-img info "$DISK_PATH"
else
    echo "Disk file not found at: $DISK_PATH"
fi
echo ""

# Provide solutions
echo "=== SOLUTIONS ==="
echo ""
echo "Option 1: Recreate VM with IDE interface (most compatible)"
echo "----------------------------------------"
cat << 'EOF'
# Stop and remove current VM
virsh --connect qemu:///session destroy Windows11
virsh --connect qemu:///session undefine Windows11 --nvram

# Recreate with IDE
virt-install \
    --connect qemu:///session \
    --name=Windows11 \
    --os-variant=win11 \
    --ram=8192 \
    --vcpus=4 \
    --cpu host-passthrough \
    --disk path=$HOME/VMs/win11.qcow2,size=60,bus=ide,format=qcow2 \
    --cdrom=/mnt/usb/Win11_24H2_EnglishInternational_x64.iso \
    --network user \
    --graphics vnc \
    --video qxl \
    --machine q35 \
    --boot uefi \
    --check all=off \
    --noautoconsole
EOF
echo ""

echo "Option 2: Add VirtIO drivers during installation"
echo "----------------------------------------"
echo "1. Download VirtIO drivers if not present:"
echo "   wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
echo ""
echo "2. Attach drivers to VM:"
echo "   virsh --connect qemu:///session attach-disk Windows11 ~/VMs/virtio-win.iso sdb --type cdrom --mode readonly"
echo ""
echo "3. During Windows installation:"
echo "   - Click 'Load driver'"
echo "   - Browse to the second CD drive"
echo "   - Navigate to: viostor/w11/amd64"
echo "   - Select the driver and install"
echo ""

echo "Option 3: Check VM during boot"
echo "----------------------------------------"
echo "1. Connect to VM console immediately after starting:"
echo "   virt-viewer --connect qemu:///session Windows11"
echo ""
echo "2. Press F2/Del during boot to enter UEFI settings"
echo "3. Check boot devices and disk controllers"
echo ""

echo "Option 4: Direct disk check"
echo "----------------------------------------"
echo "Run this to see exactly what Windows sees:"
echo "virsh --connect qemu:///session domblklist Windows11 --details"