#!/bin/bash

# Script to add USB passthrough support to Windows 11 KVM VM
# This converts the VM from VNC to SPICE graphics and adds USB redirection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VM_NAME="Windows11"

echo "=== Windows 11 VM USB Support Setup ==="
echo "This script will enable USB device passthrough for your Windows 11 VM"
echo ""

# Check if VM exists
if ! virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
    echo -e "${RED}Error: VM '$VM_NAME' not found${NC}"
    echo "Please run setup-windows11-vm.sh first to create the VM"
    exit 1
fi

# Check VM state
VM_STATE=$(virsh --connect qemu:///session domstate "$VM_NAME" 2>/dev/null || echo "unknown")
if [ "$VM_STATE" == "running" ]; then
    echo -e "${YELLOW}Warning: VM is currently running${NC}"
    echo "The VM must be shut down to add USB support."
    read -p "Shutdown VM now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Shutting down VM..."
        virsh --connect qemu:///session shutdown "$VM_NAME"
        
        # Wait for shutdown
        echo -n "Waiting for VM to shut down"
        TIMEOUT=60
        ELAPSED=0
        while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
            if virsh --connect qemu:///session domstate "$VM_NAME" 2>/dev/null | grep -q "shut off"; then
                echo -e "\n${GREEN}VM shut down successfully${NC}"
                break
            fi
            echo -n "."
            sleep 2
            ELAPSED=$((ELAPSED + 2))
        done
        
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo -e "\n${RED}Timeout waiting for shutdown. Force stopping...${NC}"
            virsh --connect qemu:///session destroy "$VM_NAME"
        fi
    else
        echo "Please shut down the VM manually and run this script again"
        exit 1
    fi
fi

# Install required packages
echo "Checking for required packages..."
PACKAGES_NEEDED=""
for pkg in spice-client-gtk gir1.2-spiceclientgtk-3.0 usbredir; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        PACKAGES_NEEDED="$PACKAGES_NEEDED $pkg"
    fi
done

if [ -n "$PACKAGES_NEEDED" ]; then
    echo "Installing required packages:$PACKAGES_NEEDED"
    sudo apt update
    sudo apt install -y $PACKAGES_NEEDED
else
    echo -e "${GREEN}All required packages are already installed${NC}"
fi

# Check if user is in plugdev group
if ! groups | grep -q plugdev; then
    echo -e "${YELLOW}Adding user to plugdev group for better USB device access...${NC}"
    sudo usermod -a -G plugdev $USER
    echo "You'll need to log out and back in for this to take effect"
fi

# Backup current VM configuration
echo "Backing up current VM configuration..."
virsh --connect qemu:///session dumpxml "$VM_NAME" > "$VM_NAME-backup-$(date +%Y%m%d-%H%M%S).xml"

# Create temporary XML file for modifications
TMP_XML="/tmp/${VM_NAME}-usb-config.xml"
virsh --connect qemu:///session dumpxml "$VM_NAME" > "$TMP_XML"

echo "Modifying VM configuration for USB support..."

# Check if SPICE graphics already exists
if grep -q "type='spice'" "$TMP_XML"; then
    echo "VM already has SPICE graphics configured"
else
    echo "Converting from VNC to SPICE graphics..."
    # Remove existing graphics configuration
    sed -i '/<graphics type=/,/<\/graphics>/d' "$TMP_XML"
    
    # Add SPICE graphics configuration before </devices>
    sed -i '/<\/devices>/i \    <graphics type="spice" autoport="yes" listen="127.0.0.1">\
      <listen type="address" address="127.0.0.1"/>\
      <image compression="auto_glz"/>\
      <jpeg compression="auto"/>\
      <zlib compression="auto"/>\
      <playback compression="on"/>\
      <streaming mode="filter"/>\
      <mouse mode="client"/>\
      <clipboard copypaste="yes"/>\
      <filetransfer enable="yes"/>\
    </graphics>' "$TMP_XML"
fi

# Check if USB controller exists
if ! grep -q "controller type='usb'" "$TMP_XML"; then
    echo "Adding USB 3.0 controller..."
    sed -i '/<\/devices>/i \    <controller type="usb" index="0" model="qemu-xhci"/>' "$TMP_XML"
fi

# Add USB redirection channels if they don't exist
if ! grep -q "redirdev" "$TMP_XML"; then
    echo "Adding USB redirection channels..."
    # Add 4 USB redirection channels for flexibility
    for i in 1 2 3 4; do
        sed -i "/<\/devices>/i \    <redirdev bus='usb' type='spicevmc'/>" "$TMP_XML"
    done
fi

# Add SPICE agent channel if it doesn't exist
if ! grep -q "spicevmc.*vdagent" "$TMP_XML"; then
    echo "Adding SPICE agent channel..."
    sed -i '/<\/devices>/i \    <channel type="spicevmc">\
      <target type="virtio" name="com.redhat.spice.0"/>\
    </channel>' "$TMP_XML"
fi

# Apply the new configuration
echo "Applying new configuration..."
if virsh --connect qemu:///session define "$TMP_XML"; then
    echo -e "${GREEN}VM configuration updated successfully!${NC}"
    rm -f "$TMP_XML"
else
    echo -e "${RED}Failed to update VM configuration${NC}"
    echo "Backup saved as: $VM_NAME-backup-$(date +%Y%m%d-%H%M%S).xml"
    exit 1
fi

# Create USB device rules helper script
cat > ~/enable-usb-device.sh << 'EOF'
#!/bin/bash
# Helper script to enable USB device access for KVM

if [ $# -ne 2 ]; then
    echo "Usage: $0 <vendor_id> <product_id>"
    echo "Example: $0 0781 5583"
    echo ""
    echo "To find your device IDs, run: lsusb"
    exit 1
fi

VENDOR_ID=$1
PRODUCT_ID=$2
RULE_FILE="/etc/udev/rules.d/50-usb-libvirt-$VENDOR_ID-$PRODUCT_ID.rules"

echo "Creating udev rule for USB device $VENDOR_ID:$PRODUCT_ID"
echo "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"$VENDOR_ID\", ATTR{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\", GROUP=\"plugdev\"" | sudo tee "$RULE_FILE"

echo "Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Done! Disconnect and reconnect your USB device for the changes to take effect."
EOF

chmod +x ~/enable-usb-device.sh

echo ""
echo "=== USB Support Successfully Enabled! ==="
echo ""
echo -e "${GREEN}To use USB devices with your Windows 11 VM:${NC}"
echo ""
echo "1. Start the VM:"
echo "   virsh --connect qemu:///session start $VM_NAME"
echo ""
echo "2. Connect with virt-viewer (NOT virt-manager for USB redirection):"
echo "   virt-viewer --connect qemu:///session $VM_NAME"
echo ""
echo "3. In virt-viewer window:"
echo "   - Go to File → USB device selection"
echo "   - Check the devices you want to redirect to Windows"
echo ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo ""
echo "If a USB device fails to redirect:"
echo "1. Find your device ID with: lsusb"
echo "2. Run: ~/enable-usb-device.sh <vendor_id> <product_id>"
echo "   Example: ~/enable-usb-device.sh 0781 5583"
echo ""
echo "Common USB devices that work well:"
echo "- USB storage drives"
echo "- Printers"
echo "- Security keys"
echo "- Game controllers"
echo ""
echo -e "${YELLOW}Note:${NC} If you were added to the plugdev group, log out and back in for full USB access."