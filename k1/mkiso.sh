#!/bin/bash

[ -d ~/k1/iso ] && sudo rm -r ~/k1/iso/* &>/dev/null

tkver="1.6.7"
netid="172.22.1"
echo "Talos Version : $tkver"

# Remaster Talos ISO
vmlist="k1m1:11 k1m2:12 k1m3:13 k1w1:15 k1w2:16 k1w3:17 k1w4:18"
for s in $vmlist
do
  vn=$(echo $s | cut -d ':' -f 1)
  ip=$(echo $s | cut -d ':' -f 2)

  sudo podman run --rm -v .:/tmp --entrypoint bash "ghcr.io/siderolabs/imager:v${tkver}" \
  -c "imager iso --arch amd64 --extra-kernel-arg 'net.ifnames=0 \
  ip=$netid.$ip::$netid.254:255.255.255.0:$vn:eth0:off:8.8.8.8:168.95.1.1:' --output /tmp" &>/dev/null

  mv ./metal-amd64.iso iso/tk8s-$vn-$netid.$ip.iso
  [ "$?" == "0" ] && echo "tk8s-$vn-$netid.$ip.iso ok"
done

