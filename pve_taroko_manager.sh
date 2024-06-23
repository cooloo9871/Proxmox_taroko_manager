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
  if ! cat /etc/os-release | grep -w ID | grep ubuntu &>/dev/null; then
    printf "${RED}Please run on Ubuntu Server 22.04 LTS${NC}\n" && exit 1
  fi

  ### check vm id
  mgid=$(echo $VM_mgmt | cut -d ':' -f1)
  taid1=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  taid2=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  taid3=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
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
  for g in $mgip $taip1 $taip2 $taip3
  do
    ping -c 1 -W 1 $VM_netid.$g &>/dev/null
    if [[ "$?" == "0" ]]; then
      printf "${RED}=====$VM_netid.$g VM IP Already used=====${NC}\n" && exit 1
    fi
  done

  ### check command
  if ! ssh -q root@"$EXECUTE_NODE" which virt-customize >/dev/null; then
    printf "${RED}=====Please install virt-customize on $EXECUTE_NODE=====${NC}\n"
    printf "${YEL}=====Run this command on $EXECUTE_NODE: sudo apt install -y libguestfs-tools=====${NC}\n"
    exit 1
  fi

  if ! which sshpass &>/dev/null; then
    printf "${RED}=====sshpass command not found,please install on localhost=====${NC}\n"
  exit 1
  fi

  if ! which podman &>/dev/null; then
    printf "${RED}=====Please install podman on localhost=====${NC}\n"
    exit 1
  else
    printf "${GRN}=====Check Environment Success=====${NC}\n"
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
      virt-customize --install qemu-guest-agent,bash,sudo,wget -a /var/vmimg/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2
    fi
EOF

  z=$(echo $VM_mgmt | cut -d ':' -f1)
  a=$(echo $VM_mgmt | cut -d ':' -f2)
  if [[ "$?" == '0' ]]; then
    ssh root@"$EXECUTE_NODE" "qm create $z --name TKAdm-$z --memory $MEM --sockets $CPU_socket --cores $CPU_core --cpu $CPU_type --net0 virtio,bridge=$Network_device" &>> /tmp/pve_vm_manager.log
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

    printf "${GRN}=====create talos management TKAdm-$z success=====${NC}\n"
  else
    printf "${RED}=====create talos management TKAdm-$z fail=====${NC}\n"
    exit 1
  fi

  printf "${GRN}[Stage: Create Talos RAW Disk]${NC}\n"

  for s in $VM_list
  do
    ip=$(echo $s | cut -d ' ' -f1 | cut -d ':' -f3)
    hostname=$(echo $s | cut -d ':' -f1)
    sudo podman run --rm -t -v "$PWD"/out:/out  -v /dev:/dev --privileged ghcr.io/siderolabs/imager:"$Talos_OS_Version" metal \
    --system-extension-image ghcr.io/siderolabs/qemu-guest-agent:"$Qemu_Agent_Version" \
    --extra-kernel-arg "ip=$VM_netid.$ip::$GATEWAY:$NETMASK:$hostname:eth0:off:$NAMESERVER::$NTP net.ifnames=0" &>> /tmp/pve_vm_manager.log

    sudo chown -R $(id -u):$(id -g) out &>> /tmp/pve_vm_manager.log
    xz -v -d "$PWD"/out/metal-amd64.raw.xz &>> /tmp/pve_vm_manager.log
    mv "$PWD"/out/metal-amd64.raw "$PWD"/out/talos-"$hostname.$ip".raw &>> /tmp/pve_vm_manager.log

    scp -q "$PWD"/out/talos-"$hostname.$ip".raw root@"$EXECUTE_NODE":/var/vmimg/ &>> /tmp/pve_vm_manager.log
    if [[ "$?" == '0' ]]; then
      printf "${GRN}=====talos-$hostname.$ip.raw create success=====${NC}\n"
    else
      printf "${RED}=====talos-$hostname.$ip.raw create fail=====${NC}\n"
      exit 1
    fi
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
    qm create "$master_vmid" && \
    qm importdisk "$master_vmid" /var/vmimg/talos-"$master_name.$master_ip".raw ${STORAGE} && \
    qm set "$master_vmid" \
    --name "$master_name" \
    --cpu "$CPU_type" --cores "$CPU_core" --sockets "$CPU_socket" \
    --memory "$MEM" \
    --net0 bridge="$Network_device",virtio,firewall=1 \
    --scsihw virtio-scsi-single \
    --scsi0 "${STORAGE}":vm-"$master_vmid"-disk-0,iothread=1 \
    --ostype l26 \
    --boot order=scsi0 \
    --agent enabled=1 && \
    qm resize "$master_vmid" scsi0 +${DISK}G
EOF
  [[ "$?" == "0" ]] && printf "${GRN}=====create $master_vmid success=====${NC}\n"
  ssh root@"$EXECUTE_NODE" /bin/bash << EOF &>> /tmp/pve_vm_manager.log
    qm create "$worker1_vmid" && \
    qm importdisk "$worker1_vmid" /var/vmimg/talos-"$worker1_name.$worker1_ip".raw ${STORAGE} && \
    qm set "$worker1_vmid" \
    --name "$worker1_name" \
    --cpu "$CPU_type" --cores "$CPU_core" --sockets "$CPU_socket" \
    --memory "$MEM" \
    --net0 bridge="$Network_device",virtio,firewall=1 \
    --scsihw virtio-scsi-single \
    --scsi0 "${STORAGE}":vm-"$worker1_vmid"-disk-0,iothread=1 \
    --ostype l26 \
    --boot order=scsi0 \
    --agent enabled=1 && \
    qm resize "$worker1_vmid" scsi0 +${DISK}G
EOF
  [[ "$?" == "0" ]] && printf "${GRN}=====create $worker1_vmid success=====${NC}\n"
  ssh root@"$EXECUTE_NODE" /bin/bash << EOF &>> /tmp/pve_vm_manager.log
    qm create "$worker2_vmid" && \
    qm importdisk "$worker2_vmid" /var/vmimg/talos-"$worker2_name.$worker2_ip".raw ${STORAGE} && \
    qm set "$worker2_vmid" \
    --name "$worker2_name" \
    --cpu "$CPU_type" --cores "$CPU_core" --sockets "$CPU_socket" \
    --memory "$MEM" \
    --net0 bridge="$Network_device",virtio,firewall=1 \
    --scsihw virtio-scsi-single \
    --scsi0 "${STORAGE}":vm-"$worker2_vmid"-disk-0,iothread=1 \
    --ostype l26 \
    --boot order=scsi0 \
    --agent enabled=1 && \
    qm resize "$worker2_vmid" scsi0 +${DISK}G
EOF
  [[ "$?" == "0" ]] && printf "${GRN}=====create $worker2_vmid success=====${NC}\n"
}

log_vm() {
  if [[ ! -f '/tmp/pve_vm_manager.log' ]]; then
    printf "${RED}=====log not found=====${NC}\n"
    exit 1
  else
    cat /tmp/pve_vm_manager.log
  fi
}

debug_vm() {
  if [[ ! -f '/tmp/pve_execute_command.log' ]]; then
    printf "${RED}=====log not found=====${NC}\n"
    exit 1
  else
    cat /tmp/pve_execute_command.log
  fi
}

start_vm() {
  mgid=$(echo $VM_mgmt | cut -d ':' -f1)
  master_vmid=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  worker1_vmid=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  worker2_vmid=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
  printf "${GRN}[Stage: Start VM]${NC}\n"

  for d in $mgid $master_vmid $worker1_vmid $worker2_vmid
  do
    if ! ssh -q -o "StrictHostKeyChecking no" root@"$EXECUTE_NODE" qm list | grep "$d" &>/dev/null; then
      printf "${RED}=====vm $d not found=====${NC}\n"
    elif
      ssh -q -o "StrictHostKeyChecking no" root@"$EXECUTE_NODE" qm list | grep "$d" | grep 'running' &>/dev/null; then
      printf "${YEL}=====vm $d already running=====${NC}\n"
    else
      ssh root@"$EXECUTE_NODE" qm start "$d" &>> /tmp/pve_vm_manager.log
      sleep 10
      printf "${GRN}=====start vm $d=====${NC}\n"
    fi
  done
}

stop_vm() {
  mgid=$(echo $VM_mgmt | cut -d ':' -f1)
  master_vmid=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  worker1_vmid=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  worker2_vmid=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
  printf "${GRN}[Stage: Stop VM]${NC}\n"
  for e in $mgid $master_vmid $worker1_vmid $worker2_vmid
  do
    if ! ssh -q -o "StrictHostKeyChecking no" root@"$EXECUTE_NODE" qm list | grep "$e" &>/dev/null; then
      printf "${RED}=====vm $e not found=====${NC}\n"
    else
      ssh root@"$EXECUTE_NODE" qm stop "$e" &>> /tmp/pve_vm_manager.log
      printf "${GRN}=====stop vm $e completed=====${NC}\n"
    fi
  done
}

deploy_vm() {
  export mgid=$(echo $VM_mgmt | cut -d ':' -f1)
  export mgip=$(echo $VM_mgmt | cut -d ':' -f2)
  export master_vmid=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  export master_ip=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f3)
  export worker1_vmid=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  export worker1_ip=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f3)
  export worker2_vmid=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
  export worker2_ip=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f3)
  export tv=$(echo $Talos_OS_Version | cut -d 'v' -f2)

  printf "${GRN}[Stage: Deploy talos k8s environment to the TKAdm-$mgid]${NC}\n"
  ### check command
  if ! which sshpass &>/dev/null; then
    printf "${RED}=====sshpass command not found,please install on localhost=====${NC}\n"
  exit 1
  fi

  ### check alp-tkadm-env.sh file
  if [[ ! -f ./alp-tkadm-env.sh ]]; then
    printf "${RED}=====alp-tkadm-env.sh file not found=====${NC}\n"
    exit 1
  fi

  for a in $mgid $master_vmid $worker1_vmid $worker2_vmid
  do
    if ! ssh -q -o "StrictHostKeyChecking no" root@"$EXECUTE_NODE" qm list | grep "$a" &>/dev/null; then
      printf "${RED}=====vm $a not found=====${NC}\n"
      exit 1
    fi
  done
  if [[ "$?" == "0" ]]; then
    sshpass -p "$PASSWORD" scp -o "StrictHostKeyChecking no" -o ConnectTimeout=5 ./alp-tkadm-env.sh "$USER"@"$VM_netid.$mgip":/home/"$USER"/alp-tkadm-env.sh &>> /tmp/pve_vm_manager.log && \
    sshpass -p "$PASSWORD" ssh "$USER"@"$VM_netid.$mgip" /bin/bash << EOF &>> /tmp/pve_vm_manager.log && \
      wget -O wulin-k1.zip https://web.antony520.com/wulin-k1.zip
      unzip wulin-k1.zip
      rm -rf wulin-k1.zip
      echo "export VM_netid="$VM_netid"" >> /home/"$USER"/envVar
      echo "export GATEWAY="$GATEWAY"" >> /home/"$USER"/envVar
      echo "export master_ip="$master_ip"" >> /home/"$USER"/envVar
      echo "export worker1_ip="$worker1_ip"" >> /home/"$USER"/envVar
      echo "export worker2_ip="$worker2_ip"" >> /home/"$USER"/envVar
EOF
    sshpass -p "$PASSWORD" ssh "$USER"@"$VM_netid.$mgip" bash /home/"$USER"/alp-tkadm-env.sh &>> /tmp/pve_vm_manager.log && \
    sshpass -p "$PASSWORD" ssh "$USER"@"$VM_netid.$mgip" rm /home/"$USER"/alp-tkadm-env.sh
    if [[ "$?" == "0" ]]; then
      printf "${GRN}=====deploy talos management TKAdm-$mgid success=====${NC}\n"
      printf "${GRN}=====TKAdm-$mgid is rebooting=====${NC}\n"
    else
      printf "${RED}=====deploy talos management TKAdm-$mgid fail=====${NC}\n"
      exit 1
    fi
  fi

  sleep 60

  printf "${GRN}[Stage: Snapshot the VM]${NC}\n"
  for l in $mgid $master_vmid $worker1_vmid $worker2_vmid
  do
    if ! ssh root@"$EXECUTE_NODE" qm list | grep "$l" &>/dev/null; then
      printf "${RED}=====vm $l not found=====${NC}\n"
    elif ! ssh root@"$EXECUTE_NODE" qm list | grep "$l" | grep running &>/dev/null; then
      printf "${RED}=====vm $l not running=====${NC}\n"
    else
      ssh root@"$EXECUTE_NODE" qm snapshot "$l" taroko-first-snapshot &>> /tmp/pve_vm_manager.log
      if [[ "$?" == "0" ]]; then
        printf "${GRN}=====snapshot vm $l completed=====${NC}\n"
      else
        printf "${RED}=====snapshot vm $l fail=====${NC}\n"
      fi
    fi
  done
}

delete_vm() {
  mgid=$(echo $VM_mgmt | cut -d ':' -f1)
  master_name=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f1)
  master_vmid=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  master_ip=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f3)
  worker1_name=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f1)
  worker1_vmid=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  worker1_ip=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f3)
  worker2_name=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f1)
  worker2_vmid=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
  worker2_ip=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f3)
  printf "${GRN}[Stage: Delete VM]${NC}\n"
  for h in $mgid $master_vmid $worker1_vmid $worker2_vmid
  do
    if ! ssh -q -o "StrictHostKeyChecking no" root@"$EXECUTE_NODE" qm list | grep "$h" &>/dev/null; then
      printf "${RED}=====vm $h not found=====${NC}\n"
    elif ssh root@"$EXECUTE_NODE" qm list | grep "$h" | grep running &>/dev/null; then
      printf "${RED}=====stop vm $h first=====${NC}\n"
    else
      ssh root@"$EXECUTE_NODE" qm destroy "$h" &>> /tmp/pve_vm_manager.log
      printf "${GRN}=====delete vm $h completed=====${NC}\n"
    fi
  done
  [[ -f /tmp/pve_execute_command.log ]] && rm /tmp/pve_execute_command.log && printf "${GRN}=====delete /tmp/pve_execute_command.log completed=====${NC}\n"
  [[ -f /tmp/pve_vm_manager.log ]] && rm /tmp/pve_vm_manager.log && printf "${GRN}=====delete /tmp/pve_vm_manager.log completed=====${NC}\n"
  ssh root@"$EXECUTE_NODE" rm /var/vmimg/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2 &>/dev/null && printf "${GRN}=====delete nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2 completed=====${NC}\n"
  ssh root@"$EXECUTE_NODE" rm /var/vmimg/talos-$master_name.$master_ip.raw /var/vmimg/talos-$worker1_name.$worker1_ip.raw /var/vmimg/talos-$worker2_name.$worker2_ip.raw &>/dev/null && \
  printf "${GRN}=====delete /var/vmimg/talos-$master_name.$master_ip.raw completed=====${NC}\n"
  printf "${GRN}=====delete /var/vmimg/talos-$worker1_name.$worker1_ip.raw completed=====${NC}\n"
  printf "${GRN}=====delete /var/vmimg/talos-$worker2_name.$worker2_ip.raw completed=====${NC}\n"
}

reset_vm() {
  master_vmid=$(echo $VM_list | cut -d ' ' -f1 | cut -d ':' -f2)
  worker1_vmid=$(echo $VM_list | cut -d ' ' -f2 | cut -d ':' -f2)
  worker2_vmid=$(echo $VM_list | cut -d ' ' -f3 | cut -d ':' -f2)
  printf "${GRN}[Stage: Reset VM]${NC}\n"

  for d in $master_vmid $worker1_vmid $worker2_vmid
  do
    if ! ssh -q -o "StrictHostKeyChecking no" root@"$EXECUTE_NODE" qm list | grep "$d" &>/dev/null; then
      printf "${RED}=====vm $d not found=====${NC}\n"
    else
      ssh root@"$EXECUTE_NODE" qm rollback "$d" taroko-first-snapshot &>> /tmp/pve_vm_manager.log
      printf "${GRN}=====reset vm $d completed=====${NC}\n"
    fi
  done
}

help() {
  cat <<EOF
Usage: pve_taroko_manager.sh [OPTIONS]

Available options:

create        create the vm based on the setenvVar parameter.
start         start all vm.
stop          stop all vm.
deploy        deploy taroko k8s environment to the vm.
delete        delete all vm.
reset         reset taroko k8s vm.
logs          show the complete execution process log.
debug         show execute command log.
EOF
  exit
}

if [[ "$#" < 1 ]]; then
  help
else
  case $1 in
    create)
      Debug
      source ./setenvVar
      [[ -f /tmp/pve_vm_manager.log ]] && rm /tmp/pve_vm_manager.log
      check_env
      create_vm
    ;;
    start)
      Debug
      source ./setenvVar
      [[ -f /tmp/pve_vm_manager.log ]] && rm /tmp/pve_vm_manager.log
      start_vm
    ;;
    stop)
      Debug
      source ./setenvVar
      [[ -f /tmp/pve_vm_manager.log ]] && rm /tmp/pve_vm_manager.log
      stop_vm
    ;;
    deploy)
      Debug
      source ./setenvVar
      [[ -f /tmp/pve_vm_manager.log ]] && rm /tmp/pve_vm_manager.log
      deploy_vm
    ;;
    delete)
      source ./setenvVar
      [[ -f /tmp/pve_vm_manager.log ]] && rm /tmp/pve_vm_manager.log
      delete_vm
    ;;
    reset)
      source ./setenvVar
      [[ -f /tmp/pve_vm_manager.log ]] && rm /tmp/pve_vm_manager.log
      reset_vm
    ;;
    logs)
      log_vm
    ;;
    debug)
      debug_vm
    ;;
    *)
      help
    ;;
  esac
fi
