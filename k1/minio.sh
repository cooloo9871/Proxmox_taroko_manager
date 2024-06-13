echo "[MinIO SNSD]"

kubectl get pods/miniosnsd -n kube-system 2>/dev/null | grep 'Running' &>/dev/null
[ "$?" == "0" ] && echo "MinIO SNSD exist" && exit 0

kubectl apply -f ~/wulin/wkload/minio/snsd/miniosnsd.yaml &>/dev/null
t=0 && echo -n "waiting "
while true; do
  status=$(kubectl get pods/miniosnsd -n kube-system -o jsonpath='{.status.conditions[0].type}')
  echo "$status" | grep -qi 'PodReady' && break
  t=$(( t+1 )) && [ $t == "60" ] && echo -e "\nMinio SNSD error" && exit 1
  sleep 5 && echo -n "."
done
echo -e "\nMiniIO SNSD ok"

sleep 20 && mc mb mios/kadm &>/dev/null
echo "mios/kadm ok"

#echo "";echo "[DirectPV]"
#kubectl label node k1w1 node-role.kubernetes.io/directpv=node &>/dev/null
#kubectl label node k1w2 node-role.kubernetes.io/directpv=node &>/dev/null

#sudo apk add kubectl-krew --update-cache --repository http://dl-3.alpinelinux.org/alpine/edge/testing/ --allow-untrusted &>/dev/null
#kubectl directpv install --node-selector node-role.kubernetes.io/directpv=node &>/dev/null
#kubectl scale deployment.apps/controller -n directpv --replicas=2
#echo -e "DirecPV ok"
