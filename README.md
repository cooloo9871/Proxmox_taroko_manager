# This project automates and manages the deployment of Taroko K8s on Proxmox.

## How to use

### Download script
```
git clone https://github.com/cooloo9871/Proxmox_taroko_manager.git;cd Proxmox_taroko_manager
```
### Setting the parameters
- `VM_mgmt` is used to setting TKAdm vm id and vm ip.
- `VM_list` is used to setting Taroko hostname,vm id and vm ip.
- `VM_netid` is the network id used by the configured vm.
- The vm ip addresses in the following example:
  - TKAdm is 192.168.61.30
  - Taroko k8s vm ip range from 192.168.61.31 to 192.168.61.33.
```
$ nano setenvVar
# Set Proxmox Cluster Env
export NODE_IP=('192.168.1.3' '192.168.1.4' '192.168.1.5')
export NODE_HOSTNAME=('p1' 'p2' 'p3')
# The EXECUTE_NODE parameter specifies the proxmox node on which to manage the vm.
export EXECUTE_NODE="p3"

# Set VM Network Env
# Please make sure that the vm id and vm ip is not conflicting.
export VM_mgmt="600:30"
export VM_list="k1m1:601:31 k1w1:602:32 k1w2:603:33"
export VM_netid="192.168.61"
export NETMASK="255.255.255.0"
export GATEWAY="192.168.61.2"
export NAMESERVER="8.8.8.8"
export Talos_OS_Version="v1.6.7"
export Qemu_Agent_Version="8.2.3"


# Set VM Hardware Env
export CPU_socket="2"
export CPU_core="2"
export CPU_type="x86-64-v2"
export MEM="4096"
export Network_device="vmbr0"
export DISK="50"
export STORAGE="local-lvm"

# Set alpine default user
export USER="bigred"
export PASSWORD="bigred"
```
