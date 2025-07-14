#!/bin/bash

# Enable SMB/CIFS folder sharing between Linux host and Windows 11 VM
# This is often the easiest method for Windows VMs

set -e

echo "=== Windows 11 VM SMB Folder Sharing Setup ==="

VM_NAME="Windows11"
SHARE_PATH="/home/ian"

# Check if VM exists
if ! virsh --connect qemu:///session list --all | grep -q "$VM_NAME"; then
    echo "Error: VM '$VM_NAME' not found"
    exit 1
fi

# Check if VM is running
VM_STATE=$(virsh --connect qemu:///session domstate "$VM_NAME")
if [ "$VM_STATE" == "running" ]; then
    echo "VM is currently running. It needs to be shut down to modify network settings."
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

# Get current VM XML
echo "Backing up current VM configuration..."
virsh --connect qemu:///session dumpxml "$VM_NAME" > "/tmp/${VM_NAME}_backup.xml"

# Create new network interface with SMB sharing
echo "Configuring network with SMB sharing..."

# First, let's check the current network configuration
echo ""
echo "Current network configuration:"
virsh --connect qemu:///session dumpxml "$VM_NAME" | grep -A5 "<interface"

# Remove existing user mode network if present
TEMP_NET_XML="/tmp/network_device.xml"

# Create new network device with SMB sharing
cat > "$TEMP_NET_XML" << EOF
<interface type='user'>
  <mac address='52:54:00:12:34:56'/>
  <model type='e1000e'/>
  <address type='pci'/>
</interface>
EOF

echo ""
echo "Updating network configuration..."

# First detach any existing user network
virsh --connect qemu:///session detach-interface "$VM_NAME" --type user --config 2>/dev/null || true

# Edit the VM to add QEMU command line arguments for SMB
TEMP_EDIT_XML="/tmp/${VM_NAME}_edit.xml"
virsh --connect qemu:///session dumpxml "$VM_NAME" > "$TEMP_EDIT_XML"

# Check if QEMU namespace is already defined
if ! grep -q "xmlns:qemu" "$TEMP_EDIT_XML"; then
    # Add QEMU namespace to domain tag
    sed -i '/<domain type=/s|>| xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0">|' "$TEMP_EDIT_XML"
fi

# Remove any existing qemu:commandline section
sed -i '/<qemu:commandline>/,/<\/qemu:commandline>/d' "$TEMP_EDIT_XML"

# Add QEMU command line arguments before </domain>
sed -i '/<\/domain>/i \
  <qemu:commandline>\
    <qemu:arg value="-netdev"/>\
    <qemu:arg value="user,id=net0,smb=/home/ian,smbserver=10.0.2.4"/>\
    <qemu:arg value="-device"/>\
    <qemu:arg value="e1000,netdev=net0"/>\
  </qemu:commandline>' "$TEMP_EDIT_XML"

# Apply the new configuration
echo "Applying new configuration..."
virsh --connect qemu:///session define "$TEMP_EDIT_XML"

# Clean up
rm -f "$TEMP_NET_XML" "$TEMP_EDIT_XML"

echo "✓ SMB sharing configured"

# Create Windows connection instructions
WIN_CONNECT_SCRIPT="$HOME/connect-smb-windows.txt"
cat > "$WIN_CONNECT_SCRIPT" << 'EOF'
=== Windows SMB Connection Instructions ===

The Linux folder is shared via SMB at: \\10.0.2.4\qemu

To connect from Windows:

Method 1 - File Explorer:
1. Open File Explorer
2. In the address bar, type: \\10.0.2.4\qemu
3. Press Enter
4. You should see your Linux home directory

Method 2 - Map Network Drive:
1. Open File Explorer
2. Right-click "This PC" → "Map network drive"
3. Choose a drive letter (e.g., Z:)
4. Folder: \\10.0.2.4\qemu
5. Check "Reconnect at sign-in" if desired
6. Click Finish

Method 3 - Command Prompt (as Administrator):
net use Z: \\10.0.2.4\qemu /persistent:yes

Method 4 - PowerShell (as Administrator):
New-PSDrive -Name Z -PSProvider FileSystem -Root "\\10.0.2.4\qemu" -Persist

Troubleshooting:
- Ensure Windows Firewall isn't blocking SMB
- Try using IP directly: \\10.0.2.4\qemu
- Check that network is working: ping 10.0.2.4
- The share name is always "qemu" when using QEMU's built-in SMB

Note: This uses QEMU's built-in SMB server, so no SMB server
needs to be running on the Linux host.
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Start the VM: virsh --connect qemu:///session start $VM_NAME"
echo "2. In Windows, open File Explorer"
echo "3. Type in address bar: \\\\10.0.2.4\\qemu"
echo "4. You'll see your Linux home folder (/home/ian)"
echo ""
echo "Connection instructions saved to: $WIN_CONNECT_SCRIPT"
echo ""
echo "Note: This method uses QEMU's built-in SMB server."
echo "No additional drivers needed in Windows!"