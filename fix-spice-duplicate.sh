#!/bin/bash

# Fix duplicate SPICE channel issue in Windows11 VM

echo "Fixing duplicate SPICE channel configuration..."

# Export current XML
virsh --connect qemu:///session dumpxml Windows11 > /tmp/windows11-original.xml

# Create fixed XML by removing the duplicate SPICE channel (keeping only the first one)
# The duplicate is on port 3, we'll remove that one
sed '/<channel type=.spicevmc.>/{
    N
    /<target type=.virtio. name=.com.redhat.spice.0.\/>/!b
    N
    /<address type=.virtio-serial. controller=.0. bus=.0. port=.3.\/>/!b
    N
    /<\/channel>/!b
    d
}' /tmp/windows11-original.xml > /tmp/windows11-fixed.xml

echo "Applying fixed configuration..."
virsh --connect qemu:///session define /tmp/windows11-fixed.xml

echo "✓ Fixed duplicate SPICE channel issue"
echo ""
echo "You can now start the VM with: ./manage-vm.sh"