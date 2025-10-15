#!/bin/bash
set -euo pipefail

VM_DIR="$(pwd)/vm"
IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMG_FILE="$VM_DIR/ubuntu-image.img"
UBUNTU_PERSISTENT_DISK="$VM_DIR/persistent.qcow2"
SEED_FILE="$VM_DIR/seed.iso"
MEMORY=256G
CPUS=32
SSH_PORT=2222
DISK_SIZE=800G
IMG_SIZE=20G
HOSTNAME="noxy"
USERNAME="root"
PASSWORD="554466DSAFf"
SWAP_SIZE=4G
HUGEPAGE_PATH="/dev/hugepages"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
NUMA_NODES=2

mkdir -p "$VM_DIR"
cd "$VM_DIR"

for pkg in qemu-system-x86 qemu-utils cloud-image-utils ovmf genisoimage; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        sudo apt update && sudo apt install -y "$pkg"
    fi
done

if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCELERATION_FLAG="-enable-kvm -cpu host"
else
    ACCELERATION_FLAG="-accel tcg"
fi

HUGEPAGES_NEEDED=$(( $(echo $MEMORY | sed 's/G//') * 1024 / 2 ))
if ! grep -q "hugepages" /etc/default/grub; then
    read -p "Configure hugepages now? (y/n): " answer
    if [ "$answer" = "y" ]; then
        sudo mkdir -p /dev/hugepages
        sudo mount -t hugetlbfs none /dev/hugepages
        sudo bash -c "echo 'hugepages=$HUGEPAGES_NEEDED' >> /etc/default/grub.d/50-hugepages.cfg"
        sudo update-grub
        exit 1
    fi
fi

if [ ! -f "$IMG_FILE" ]; then
    wget "$IMG_URL" -O "$IMG_FILE"
    qemu-img resize "$IMG_FILE" "$DISK_SIZE"
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
disable_root: false
ssh_pwauth: true
chpasswd:
  list: |
    $USERNAME:$PASSWORD
  expire: false
packages:
  - openssh-server
  - qemu-guest-agent
  - nginx
  - php-fpm
  - mariadb-server
  - redis
cloud_init_modules:
  - bootcmd
runcmd:
  - echo "$USERNAME:$PASSWORD" | chpasswd
  - if [ "$SWAP_SIZE" != "0G" ]; then fallocate -l $SWAP_SIZE /swapfile; chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile; echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
  - systemctl enable --now nginx php8.1-fpm mariadb redis
  - curl -sL https://deb.nodesource.com/setup_18.x | bash -
  - apt install -y nodejs
  - npm install -g pm2
  - curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
  - apt update && apt install -y mariadb-server
  - mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$PASSWORD';"
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false
resize_rootfs: true
EOF
    cat > meta-data <<EOF
instance-id: iid-local01
local-hostname: $HOSTNAME
EOF
    cloud-localds "$SEED_FILE" user-data meta-data
fi

if [ ! -f "$UBUNTU_PERSISTENT_DISK" ]; then
    qemu-img create -f qcow2 "$UBUNTU_PERSISTENT_DISK" "$IMG_SIZE"
fi

cleanup() {
    pkill -f "qemu-system-x86_64" || true
}
trap cleanup SIGINT SIGTERM

exec qemu-system-x86_64 \
    $ACCELERATION_FLAG \
    -machine q35,mem-merge=off,hmat=on \
    -m "$MEMORY" -mem-prealloc \
    -object memory-backend-file,id=ram-node0,size=128G,mem-path=$HUGEPAGE_PATH,share=on,prealloc=on \
    -object memory-backend-file,id=ram-node1,size=128G,mem-path=$HUGEPAGE_PATH,share=on,prealloc=on \
    -numa node,nodeid=0,memdev=ram-node0 \
    -numa node,nodeid=1,memdev=ram-node1 \
    -smp "$CPUS",sockets=2,cores=16,threads=1 \
    -drive file="$IMG_FILE",format=qcow2,if=virtio,cache=writeback \
    -drive file="$UBUNTU_PERSISTENT_DISK",format=qcow2,if=virtio,cache=writeback \
    -drive file="$SEED_FILE",format=raw,if=virtio \
    -boot order=c,strict=on \
    -device virtio-net-pci,netdev=n0 \
    -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22 \
    -nodefaults \
    -bios "$OVMF_CODE" \
    -nographic -serial mon:stdio
