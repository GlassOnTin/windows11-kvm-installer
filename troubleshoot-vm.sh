#!/bin/bash

# Windows 11 VM Troubleshooting Script

echo "=== Windows 11 VM Troubleshooting ==="
echo ""

# Check virtualization support
echo "1. Checking CPU virtualization support..."
if grep -q -E '(vmx|svm)' /proc/cpuinfo; then
    echo "✓ CPU virtualization is supported"
else
    echo "✗ CPU virtualization not detected - check BIOS settings"
fi
echo ""

# Check KVM kernel module
echo "2. Checking KVM kernel modules..."
if lsmod | grep -q kvm; then
    echo "✓ KVM modules loaded"
else
    echo "✗ KVM modules not loaded"
    echo "  Try: sudo modprobe kvm_intel (or kvm_amd)"
fi
echo ""

# Check libvirt service
echo "3. Checking libvirt service..."
if systemctl is-active --quiet libvirtd; then
    echo "✓ libvirtd is running"
else
    echo "✗ libvirtd is not running"
    echo "  Try: sudo systemctl start libvirtd"
fi
echo ""

# Check user groups
echo "4. Checking user group membership..."
if groups | grep -q -E '(kvm|libvirt)'; then
    echo "✓ User is in kvm/libvirt groups"
    groups | grep -E '(kvm|libvirt)'
else
    echo "✗ User not in required groups"
    echo "  Try: sudo usermod -a -G kvm,libvirt $USER"
    echo "  Then logout and login again"
fi
echo ""

# Check VMs
echo "5. Checking existing VMs..."
virsh --connect qemu:///session list --all
echo ""

# Check disk images
echo "6. Checking VM disk images..."
if [ -d "$HOME/VMs" ]; then
    echo "VM directory contents:"
    ls -la "$HOME/VMs"
else
    echo "VM directory not found"
fi
echo ""

# Check network
echo "7. Checking default network..."
virsh --connect qemu:///system net-list --all 2>/dev/null || echo "Cannot check system networks (permission issue)"
echo ""

# Check VNC ports
echo "8. Checking VNC ports..."
ss -tlnp | grep 590 || echo "No VNC ports found listening"
echo ""

# VM-specific checks
VM_NAME="Windows11"
echo "9. Checking Windows11 VM status..."
if virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
    echo "VM exists. Current state:"
    virsh --connect qemu:///session domstate "$VM_NAME"
    
    if virsh --connect qemu:///session domstate "$VM_NAME" | grep -q "running"; then
        echo "VNC display:"
        virsh --connect qemu:///session vncdisplay "$VM_NAME"
    fi
else
    echo "VM not found"
fi
echo ""

echo "=== Troubleshooting Summary ==="
echo "If you're having issues:"
echo "1. Ensure virtualization is enabled in BIOS"
echo "2. Make sure you've logged out/in after group changes"
echo "3. Check that libvirtd service is running"
echo "4. Verify the Windows 11 ISO is accessible"
echo "5. Try connecting with: virt-viewer --connect qemu:///session Windows11"