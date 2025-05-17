#!/bin/bash

# Windows 11 VM Management Script
# Helper script to manage your Windows 11 VM

VM_NAME="Windows11"

echo "=== Windows 11 VM Management ==="
echo ""

# Check VM status
if virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
    STATUS=$(virsh --connect qemu:///session domstate "$VM_NAME")
    echo "VM Status: $STATUS"
    echo ""
    echo "Available actions:"
    echo "1. Start VM"
    echo "2. Stop VM (graceful shutdown)"
    echo "3. View VM (connect with virt-viewer)"
    echo "4. Delete VM and disk"
    echo "5. Exit"
    echo ""
    read -p "Choose action (1-5): " choice
    
    case $choice in
        1)
            echo "Starting VM..."
            virsh --connect qemu:///session start "$VM_NAME"
            echo "✓ VM started"
            echo "Connect with: virt-viewer --connect qemu:///session $VM_NAME"
            ;;
        2)
            echo "Stopping VM..."
            virsh --connect qemu:///session shutdown "$VM_NAME"
            echo "✓ Shutdown signal sent"
            ;;
        3)
            echo "Connecting to VM..."
            virt-viewer --connect qemu:///session "$VM_NAME" &
            echo "✓ Viewer launched"
            ;;
        4)
            read -p "Are you sure you want to delete the VM and disk? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                echo "Deleting VM..."
                virsh --connect qemu:///session destroy "$VM_NAME" 2>/dev/null || true
                virsh --connect qemu:///session undefine "$VM_NAME" --nvram 2>/dev/null || true
                rm -f ~/VMs/win11.qcow2
                rm -f ~/VMs/virtio-win.iso
                echo "✓ VM and disk deleted"
            else
                echo "Cancelled"
            fi
            ;;
        5)
            echo "Exiting..."
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
else
    echo "No Windows 11 VM found."
    echo "Run ./setup-windows11-vm.sh to create one."
fi