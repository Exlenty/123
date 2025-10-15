#!/bin/bash
set -euo pipefail

# =============================
# Enhanced Multi-VM Manager
# =============================

VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Determine acceleration
if [ -e /dev/kvm ]; then
    ACCELERATION_FLAG="-enable-kvm -cpu host"
else
    ACCELERATION_FLAG="-accel tcg"
fi

# Display header
display_header() {
    clear
    cat << "EOF"
========================================================================
  _    _  ____  _____ _____ _   _  _____ ____   ______     ________
 | |  | |/ __ \|  __ \_   _| \ | |/ ____|  _ \ / __ \ \   / /___  /
 | |__| | |  | | |__) || | |  \| | |  __| |_) | |  | \ \_/ /   / / 
 |  __  | |  | |  ___/ | | |   \ | | |_ |  _ <| |  | |\   /   / /  
 | |  | | |__| | |    _| |_| |\  | |__| | |_) | |__| | | |   / /__ 
 |_|  |_|\____/|_|   |_____|_| \_|\_____|____/ \____/  |_|  /_____|
                                                                  
                    POWERED BY HOPINGBOYZ
========================================================================
EOF
    echo
}

# Print status messages with color
print_status() {
    local type=$1
    local message=$2
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

# Validate input
validate_input() {
    local type=$1
    local value=$2
    case $type in
        "number") [[ "$value" =~ ^[0-9]+$ ]] || return 1 ;;
        "size") [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || return 1 ;;
        "port") [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 23 ] && [ "$value" -le 65535 ] || return 1 ;;
        "name") [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1 ;;
        "username") [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1 ;;
    esac
    return 0
}

# Check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "ss" "openssl")
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done
    if [ ${#missing[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

# Cleanup temp files
cleanup() {
    rm -f user-data meta-data
}
trap cleanup EXIT

# Supported OS
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
)

# Save VM config
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
EOF
    print_status "SUCCESS" "Configuration saved: $config_file"
}

# Load VM config
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    [[ -f "$config_file" ]] || { print_status "ERROR" "VM $vm_name not found"; return 1; }
    source "$config_file"
}

# Create new VM
create_new_vm() {
    print_status "INFO" "Creating new VM..."
    echo "Available OS options:"
    local i=1; declare -a os_options_arr
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"; os_options_arr[$i]="$os"; ((i++))
    done
    while true; do
        read -p "$(print_status "INPUT" "Choose OS (1-${#os_options_arr[@]}): ")" choice
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#os_options_arr[@]} ] && break
        print_status "ERROR" "Invalid choice"
    done
    IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[${os_options_arr[$choice]}]}"
    # Inputs
    read -p "$(print_status "INPUT" "VM Name [$DEFAULT_HOSTNAME]: ")" VM_NAME; VM_NAME=${VM_NAME:-$DEFAULT_HOSTNAME}
    read -p "$(print_status "INPUT" "Hostname [$VM_NAME]: ")" HOSTNAME; HOSTNAME=${HOSTNAME:-$VM_NAME}
    read -p "$(print_status "INPUT" "Username [$DEFAULT_USERNAME]: ")" USERNAME; USERNAME=${USERNAME:-$DEFAULT_USERNAME}
    read -s -p "$(print_status "INPUT" "Password [$DEFAULT_PASSWORD]: ")" PASSWORD; PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}; echo
    read -p "$(print_status "INPUT" "Disk size [20G]: ")" DISK_SIZE; DISK_SIZE=${DISK_SIZE:-20G}
    read -p "$(print_status "INPUT" "Memory MB [2048]: ")" MEMORY; MEMORY=${MEMORY:-2048}
    read -p "$(print_status "INPUT" "CPUs [2]: ")" CPUS; CPUS=${CPUS:-2}
    read -p "$(print_status "INPUT" "SSH Port [2222]: ")" SSH_PORT; SSH_PORT=${SSH_PORT:-2222}
    read -p "$(print_status "INPUT" "GUI mode y/n [n]: ")" gui; GUI_MODE=false; [[ "$gui" =~ [Yy] ]] && GUI_MODE=true
    read -p "$(print_status "INPUT" "Extra port forwards (host:guest, comma separated): ")" PORT_FORWARDS
    IMG_FILE="$VM_DIR/$VM_NAME.img"; SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"; CREATED=$(date)
    setup_vm_image
    save_vm_config
}

# Setup VM image & cloud-init
setup_vm_image() {
    mkdir -p "$VM_DIR"
    [[ -f "$IMG_FILE" ]] || wget -O "$IMG_FILE.tmp" "$IMG_URL" && mv "$IMG_FILE.tmp" "$IMG_FILE"
    qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null || qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    # cloud-init
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD")
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF
    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF
    cloud-localds "$SEED_FILE" user-data meta-data
    print_status "SUCCESS" "VM $VM_NAME ready"
}

# Start VM
start_vm() {
    local vm=$1
    load_vm_config "$vm" || return
    print_status "INFO" "Starting $vm (SSH: ssh -p $SSH_PORT $USERNAME@localhost)"
    local cmd=(qemu-system-x86_64 $ACCELERATION_FLAG -m "$MEMORY" -smp "$CPUS" \
        -drive "file=$IMG_FILE,format=qcow2,if=virtio" \
        -drive "file=$SEED_FILE,format=raw,if=virtio" \
        -boot order=c \
        -device virtio-net-pci,netdev=n0 \
        -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22")
    [[ -n "$PORT_FORWARDS" ]] && IFS=',' read -ra pf <<< "$PORT_FORWARDS" && \
        for f in "${pf[@]}"; do IFS=':' read -r h g <<< "$f"; cmd+=(-netdev "user,id=n1,hostfwd=tcp::$h-:$g"); done
    $([[ "$GUI_MODE" == true ]] && echo "${cmd[@]} -vga virtio -display gtk,gl=on" || echo "${cmd[@]} -nographic -serial mon:stdio") | bash
}

# List VMs
list_vms() {
    echo "Available VMs:"
    ls "$VM_DIR"/*.conf 2>/dev/null | xargs -n1 basename | sed 's/\.conf//'
}

# Main menu
main_menu() {
    while true; do
        display_header
        echo "1) Create new VM"
        echo "2) Start VM"
        echo "3) List VMs"
        echo "4) Exit"
        read -p "Choose: " choice
        case $choice in
            1) create_new_vm ;;
            2) read -p "VM Name: " vm && start_vm "$vm" ;;
            3) list_vms ;;
            4) exit 0 ;;
            *) print_status "ERROR" "Invalid choice" ;;
        esac
        read -p "Press Enter to continue..."
    done
}

# Run
check_dependencies
main_menu
