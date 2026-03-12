###

echo "Check all VM's..."
set -x
multipass list
set +x

echo "Check all pods are running..."
set -x
kubectl get pods -n demo -o wide
echo
set +x
echo "Check services..."
set -x
kubectl get svc -n demo
echo 
set +x
echo "Quick health check on backend..."
(
multipass list \
| grep worker \
| awk '{print $3}'
) | \
(
while read NODE_IP
do 
   echo ${NODE_IP}
   echo "Check some endpoints..."
   set -x
   curl http://${NODE_IP}:30500/health
   curl http://${NODE_IP}:30500/votes
   set +x
   echo 
   echo "Cast some test votes..."
   set -x
   curl -X POST http://${NODE_IP}:30500/vote/cats
   curl -X POST http://${NODE_IP}:30500/vote/dogs
   curl -X POST http://${NODE_IP}:30500/vote/cats
   curl http://${NODE_IP}:30500/votes
   set +x
   echo
done
) | \
grep -v "++ set +x"
