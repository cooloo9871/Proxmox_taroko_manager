echo "";echo "[Kube-kadm]"
kubectl apply -f ~/wulin/wkload/kadm/kube-kadm-dkreg.yaml &>/dev/null
t=0 && echo -n "waiting "
while true; do
  status=$(kubectl get pods/kube-kadm -n kube-system -o jsonpath='{.status.conditions[0].type}')
  echo "$status" | grep -qi 'PodReady' && break
  t=$(( t+1 )) && [ $t == "20" ] && echo "kube-kadm error" && exit 1
  sleep 5 && echo -n "."
done
sleep 30 && echo -e "\nKube-kadm ok\n"
