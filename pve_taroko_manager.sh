#!/bin/bash

RED='\033[1;31m' # alarm
GRN='\033[1;32m' # notice
YEL='\033[1;33m' # warning
NC='\033[0m' # No Color

# function
# debug mode
Debug() {
  ### output log
  [[ -f ~/.ssh/known_hosts ]] && rm ~/.ssh/known_hosts
  [[ -f /tmp/pve_execute_command.log ]] && rm /tmp/pve_execute_command.log
  exec {BASH_XTRACEFD}>> /tmp/pve_execute_command.log
  set -x
  #set -o pipefail
}


# check environment
check_env() {
  printf "${GRN}[Stage: Check Environment]${NC}\n"
  [[ ! -f ./setenvVar ]] && printf "${RED}setenvVar file not found${NC}\n" && exit 1
  var_names=$(cat setenvVar | grep -v '#' | cut -d " " -f 2 | cut -d "=" -f 1 | tr -s "\n" " " | sed 's/[ \t]*$//g')
  for var_name in ${var_names[@]}
  do
    [ -z "${!var_name}" ] && printf "${RED}$var_name is unset.${NC}\n" && exit 1
  done

  ### check ssh login to Proxmox node without password
  for n in ${NODE_IP[@]}
  do
    ssh -q -o BatchMode=yes -o "StrictHostKeyChecking no" root@"$n" '/bin/true' &> /dev/null
    if [[ "$?" != "0" ]]; then
      printf "${RED}Must be configured to use ssh to login to the Proxmox node1 without a password.${NC}\n"
      printf "${YEL}=====Run this command: ssh-keygen -t rsa -P ''=====${NC}\n"
      printf "${YEL}=====Run this command: ssh-copy-id root@"$n"=====${NC}\n"
      exit 1
    fi
  done

  ### check ssh login to Proxmox node use hostname
  for i in ${NODE_HOSTNAME[@]}
  do
    ssh -q -o BatchMode=yes -o "StrictHostKeyChecking no" root@"$i" '/bin/true' &> /dev/null
    [[ "$?" != "0" ]] && printf "${RED}Must be configured to use hostname to ssh login to the Proxmox $i.${NC}\n" && exit 1
  done

  ### check os
  if ! cat /etc/os-release | grep -w ID | grep ubuntu; then
    printf "${RED}Please run on Ubuntu Server 22.04 LTS${NC}\n" && exit 1
  fi

  ### check vm id
  mgid=$(echo $VM_mgmt | cut -d ':' -f2)
  taid1=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f3)
  taid2=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f3)
  taid3=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f3)
  for f in $mgid $taid1 $taid2 $taid3
  do
    for c in ${NODE_HOSTNAME[@]}
    do
      ssh -q root@"$c" qm list | awk '{print $1}' | grep -v VMID | grep "$f" &>/dev/null
      if [[ "$?" == "0" ]]; then
        printf "${RED}=====$f VM ID Already used=====${NC}\n" && exit 1
      fi
    done
  done

  ### check vm ip
  mgip=$(echo $VM_mgmt | cut -d ':' -f1)
  taip1=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  taip2=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  taip3=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
  for ((g=$ipstart;g<=$ipend;g++))
  do
    ping -c 1 -W 1 $VM_netid.$g &>/dev/null
    if [[ "$?" == "0" ]]; then
      printf "${RED}=====$VM_netid.$g VM IP Already used=====${NC}\n" && exit 1
    fi
  done

  ### check command
  which podman >/dev/null
  if [[ ! "$?" == "0" ]]; then
    printf "${RED}=====Please install podman on localhost=====${NC}\n"
    exit 1
  else
    printf "${GRN}=====Check Environment Success=====${NC}\n"
  fi
  if ! which sshpass &>/dev/null; then
    printf "${RED}=====sshpass command not found,please install on localhost=====${NC}\n"
    exit 1
  fi

}

# create VM
create_vm() {
  printf "${GRN}[Stage: Create Talos Management]${NC}\n"

  ssh root@"$EXECUTE_NODE" /bin/bash << EOF &>> /tmp/pve_vm_manager.log
    if [[ ! -d /var/vmimg/ ]]; then
      mkdir /var/vmimg/
    fi
    if [[ ! -d /var/lib/vz/snippets/ ]]; then
      mkdir -p /var/lib/vz/snippets/
    fi
    if [[ ! -f /var/vmimg/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2 ]]; then
      wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/cloud/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2 -O /var/vmimg/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2
      if [[ "$?" != '0' ]]; then
        printf "${RED}=====download cloud init image fail=====${NC}\n" && exit 1
      fi
      virt-customize --install qemu-guest-agent,bash,sudo -a /var/vmimg/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2
    fi
EOF
  if [[ "$?" == '0' ]]; then
    z=$(echo $VM_mgmt | cut -d ':' -f1)
    a=$(echo $VM_mgmt | cut -d ':' -f2)
    ssh root@"$EXECUTE_NODE" "qm create $z --name alp-talos-$z --memory $MEM --sockets $CPU_socket --cores $CPU_core --cpu $CPU_type --net0 virtio,bridge=$Network_device" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" "qm importdisk $z /var/vmimg/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2 ${STORAGE}" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" "qm set $z --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-$z-disk-0" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" "qm resize $z scsi0 ${DISK}G" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" "qm set $z --ide2 ${STORAGE}:cloudinit" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" "qm set $z --boot c --bootdisk scsi0" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" "qm set $z --serial0 socket --vga serial0" &>> /tmp/pve_vm_manager.log

    scp ./user.yml root@"$EXECUTE_NODE":"/var/lib/vz/snippets/user$z.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" sed -i "s/NS/$NAMESERVER/g" "/var/lib/vz/snippets/user$z.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" sed -i "s/AC/$USER/g" "/var/lib/vz/snippets/user$z.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" sed -i "s/PW/$PASSWORD/g" "/var/lib/vz/snippets/user$z.yml" &>> /tmp/pve_vm_manager.log

    scp ./network.yml root@"$EXECUTE_NODE":"/var/lib/vz/snippets/network$a.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" sed -i "s/netid/$VM_netid/g" "/var/lib/vz/snippets/network$a.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" sed -i "s/ip/$a/g" "/var/lib/vz/snippets/network$a.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" sed -i "s/nk/$NETMASK/g" "/var/lib/vz/snippets/network$a.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" sed -i "s/gw/$GATEWAY/g" "/var/lib/vz/snippets/network$a.yml" &>> /tmp/pve_vm_manager.log

    ssh root@"$EXECUTE_NODE" qm set "$z" --cicustom "user=local:snippets/user$z.yml,network=local:snippets/network$a.yml" &>> /tmp/pve_vm_manager.log
    ssh root@"$EXECUTE_NODE" qm start "$z"

    ### check alp-kind-env.sh file
    if [[ ! -f ./alp-kind-env.sh ]]; then
      printf "${RED}=====alp-kind-env.sh file not found=====${NC}\n"
      exit 1
    fi
    sleep 60

    sshpass -p "$PASSWORD" scp -o "StrictHostKeyChecking no" -o ConnectTimeout=5 ./alp-kind-env.sh "$USER"@"$VM_netid.$a":/home/"$USER"/alp-kind-env.sh &>> /tmp/pve_vm_manager.log && \
    sshpass -p "$PASSWORD" ssh "$USER"@"$VM_netid.$a" bash /home/"$USER"/alp-kind-env.sh &>> /tmp/pve_vm_manager.log && \
    sshpass -p "$PASSWORD" ssh "$USER"@"$VM_netid.$a" rm /home/"$USER"/alp-kind-env.sh

    printf "${GRN}=====create talos management alp-talos-$z success=====${NC}\n"
  fi

  printf "${GRN}[Stage: Create Talos ISO]${NC}\n"

  for s in $VM_list
  do
    ip=$(echo $VM_list | cut -d ':' -f3)
    hostname=$(echo $VM_list | cut -d ':' -f1)
    sudo podman run --rm -t -v $PWD/out:/out  -v /dev:/dev --privileged ghcr.io/siderolabs/imager:"$Talos_OS_Version" metal \
    --system-extension-image ghcr.io/siderolabs/qemu-guest-agent:"$Qemu_Agent_Version" \
    --extra-kernel-arg "ip=$VM_netid.$ip::$GATEWAY:$NETMASK:$hostname:eth0:off:$NAMESERVER net.ifnames=0"

    sudo chown -R $(id -u):$(id -g) out
    xz -v -d $PWD/out/metal-amd64.raw.xz
    mv $PWD/out/metal-amd64.raw $PWD/out/talos-$hostname.$ip.raw

    scp $PWD/out/talos-$vn.$ip.raw root@$NODE_1_IP:/var/vmimg/
    printf "${GRN}=====talos-$vn.$ip.raw Create Success=====${NC}\n"
  done

  printf "${GRN}=====[Stage: Create Talos VM]=====${NC}\n"
  master_name=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f1)
  master_vmid=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  master_ip=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f3)
  worker1_name=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f1)
  worker1_vmid=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  worker1_ip=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f3)
  worker2_name=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f1)
  worker2_vmid=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
  worker2_ip=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f3)

  ssh root@"$EXECUTE_NODE" /bin/bash << EOF &>> /tmp/pve_vm_manager.log
    qm set $master_vmid \
    --name $master_name \
    --cpu $CPU_type --cores $CPU_core --sockets $CPU_socket \
    --memory $MEM \
    --net0 bridge="$Network_device",virtio,firewall=1 \
    --scsihw virtio-scsi-single \
    --scsi0 ${STORAGE}:vm-"$master_vmid"-disk-0,iothread=1 \
    --ostype l26 \
    --boot order=scsi0 \
    --agent enabled=1

    qm resize $master_vmid scsi0 ${DISK}G
    qm start $master_vmid
EOF
  [[ "$?" == "0" ]] && printf "${GRN}=====Create $master_vmid success=====${NC}\n"

  ssh root@"$EXECUTE_NODE" /bin/bash << EOF &>> /tmp/pve_vm_manager.log
    qm set $worker1_vmid \
    --name $worker1_name \
    --cpu $CPU_type --cores $CPU_core --sockets $CPU_socket \
    --memory $MEM \
    --net0 bridge="$Network_device",virtio,firewall=1 \
    --scsihw virtio-scsi-single \
    --scsi0 ${STORAGE}:vm-"$worker1_vmid"-disk-0,iothread=1 \
    --ostype l26 \
    --boot order=scsi0 \
    --agent enabled=1

    qm resize $worker1_vmid scsi0 ${DISK}G
    qm start $worker1_vmid
EOF
  [[ "$?" == "0" ]] && printf "${GRN}=====Create $worker1_vmid success=====${NC}\n"

  ssh root@"$EXECUTE_NODE" /bin/bash << EOF &>> /tmp/pve_vm_manager.log
    qm set $worker2_vmid \
    --name $worker2_name \
    --cpu $CPU_type --cores $CPU_core --sockets $CPU_socket \
    --memory $MEM \
    --net0 bridge="$Network_device",virtio,firewall=1 \
    --scsihw virtio-scsi-single \
    --scsi0 ${STORAGE}:vm-"$worker2_vmid"-disk-0,iothread=1 \
    --ostype l26 \
    --boot order=scsi0 \
    --agent enabled=1

    qm resize $worker2_vmid scsi0 ${DISK}G
    qm start $worker2_vmid
EOF
  [[ "$?" == "0" ]] && printf "${GRN}=====Create $worker2_vmid success=====${NC}\n"

}

Debug
source ./setenvVar
check_env
create_vm
