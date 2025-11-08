#!/bin/sh

: <<'EOF' #Introductory comment block:
Asustor Flashstor kernel module check/compile script for Proxmox 9
Checks to see if the necessary it87 kmod exists, installs it if not, and runs the fan control script
By Bernard Mc Clement, Sept 2023. 
Converted to Proxmox 11/2025

Note that you can check if the asustor-it87 kmod is installed by running the following command in the Proxmox shell:
 if lsmod | grep -q asustor_it87; then
    echo "asustor-it87 kmod is already installed."
  else
    echo "asustor-it87 kmod not found or not installed."
 fi
EOF


# Add this as a post-init script so that it runs on every boot

# Check if the kmod exists and is installed
if ! lsmod | grep -q asustor_it87; then
    echo "asustor-it87 kmod not found or not installed. Compiling and installing..."

    # Clone the repository
    git clone https://github.com/hgtxrx/asustor-platform-driver
    cd asustor-platform-driver

    # Install dkms
    apt install -y dkms

    # Compile the kmod
    make

    # Install the kmod using dkms
    make dkms

    echo "asustor-it87 kmod compiled and installed successfully."
else
    echo "asustor-it87 kmod is already installed."
fi

# Run the fan control script
nohup /root/temp_monitor.sh >/dev/null 2>&1 &
