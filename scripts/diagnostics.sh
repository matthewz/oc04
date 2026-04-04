#!/usr/bin/env bash
# =============================================================
# Kubernetes Infrastructure Diagnostic Script
# Categories: Cluster, Compute, Storage, Network, Security,
#             Application, Timing/Latency, Error Rates,
#             Throughput, Summary
# =============================================================
set -euo pipefail
# Pre-flight: resolve common pod references once
BACKEND_POD=$(kubectl get pod -n demo -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
REDIS_POD=$(kubectl get pod -n demo -l app=redis   -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
FRONTEND_POD=$(kubectl get pod -n demo -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
REDIS_SVC_IP=$(kubectl get svc -n demo redis -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
REDIS_IP=$([ -n "$REDIS_POD" ] && kubectl get pod -n demo "$REDIS_POD" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
# ============================================================
# 1. CLUSTER-LEVEL
# ============================================================
echo "========================================"
echo "=== CLUSTER-LEVEL DIAGNOSTICS ==="
echo "========================================"
echo "=== kubectl Version ==="
#kubectl version --short
kubectl version
echo ""
echo "=== kubeconfig Context ==="
kubectl config current-context
kubectl config get-contexts
kubectl config get-clusters
kubectl config view --minify
echo ""
echo "=== API Server Reachability ==="
kubectl cluster-info
echo ""
echo "=== Component Status ==="
kubectl get componentstatuses 2>/dev/null || echo "componentstatuses not available"
echo ""
echo "=== Namespace List ==="
kubectl get namespaces
echo ""
echo "=== All Resources in Demo Namespace ==="
kubectl get all -n demo
echo ""
echo "=== Node Status ==="
kubectl get nodes -o wide
echo ""
echo "=== Node Kubelet Version ==="
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" Kubelet: "}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'
echo ""
echo "=== Node Container Runtime ==="
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" Runtime: "}{.status.nodeInfo.containerRuntimeVersion}{"\n"}{end}'
echo ""
echo "=== Node Kernel Version ==="
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" Kernel: "}{.status.nodeInfo.kernelVersion}{"\n"}{end}'
echo ""
echo "=== Node CPU Architecture ==="
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" Arch: "}{.status.nodeInfo.architecture}{" OS: "}{.status.nodeInfo.operatingSystem}{"\n"}{end}'
echo ""
echo "=== Node Taints ==="
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\nTaints: "}{.spec.taints}{"\n"}{end}'
echo ""
echo "=== Node Labels ==="
kubectl get nodes --show-labels
echo ""
echo "=== Node Conditions ==="
kubectl describe nodes | grep -A5 "Conditions:"
echo ""
echo "=== Node Disk/Memory/PID Pressure ==="
kubectl describe nodes | grep -E "DiskPressure|MemoryPressure|PIDPressure|Ready"
echo ""
echo "=== Node Resource Capacity ==="
kubectl describe nodes | grep -A10 "Capacity:"
echo ""
echo "=== Node Allocatable Resources ==="
kubectl describe nodes | grep -A10 "Allocatable:"
echo ""
echo "=== Pods per Node ==="
kubectl get pods -n demo -o wide | awk '{print $7}' | sort | uniq -c
echo ""
echo "=== System Pods per Node ==="
kubectl get pods -n kube-system -o wide | awk '{print $7}' | sort | uniq -c
echo ""
echo "=== etcd Status ==="
kubectl get pods -n kube-system | grep etcd
echo ""
echo "=== etcd Logs ==="
kubectl logs -n kube-system -l component=etcd --tail=10 2>/dev/null || echo "No etcd logs found"
echo ""
echo "=== API Server Logs ==="
kubectl logs -n kube-system -l component=kube-apiserver --tail=10 2>/dev/null || echo "No apiserver logs found"
echo ""
echo "=== Controller Manager Logs ==="
kubectl logs -n kube-system -l component=kube-controller-manager --tail=10 2>/dev/null || echo "No controller-manager logs found"
echo ""
echo "=== Scheduler Logs ==="
kubectl logs -n kube-system -l component=kube-scheduler --tail=10 2>/dev/null || echo "No scheduler logs found"
echo ""
echo "=== kube-system Pod Status ==="
kubectl get pods -n kube-system -o wide
echo ""
echo "=== Multipass Version ==="
multipass version
echo ""
echo "=== Multipass Driver ==="
multipass get local.driver
echo ""
echo "=== Multipass VMs ==="
multipass list
echo ""
# ============================================================
# 2. COMPUTE
# ============================================================
echo "========================================"
echo "=== COMPUTE DIAGNOSTICS ==="
echo "========================================"
echo "=== Detailed VM Info ==="
multipass info k8s-worker1
multipass info k8s-worker2
echo ""
echo "=== OS Version on Worker1 ==="
multipass exec k8s-worker1 -- cat /etc/os-release
echo ""
echo "=== OS Version on Worker2 ==="
multipass exec k8s-worker2 -- cat /etc/os-release
echo ""
echo "=== CPU Count on Worker1 ==="
multipass exec k8s-worker1 -- nproc
echo ""
echo "=== CPU Count on Worker2 ==="
multipass exec k8s-worker2 -- nproc
echo ""
echo "=== System Load on Worker1 ==="
multipass exec k8s-worker1 -- uptime
echo ""
echo "=== System Load on Worker2 ==="
multipass exec k8s-worker2 -- uptime
echo ""
echo "=== CPU Usage on Worker1 ==="
multipass exec k8s-worker1 -- top -bn1 | head -10
echo ""
echo "=== CPU Usage on Worker2 ==="
multipass exec k8s-worker2 -- top -bn1 | head -10
echo ""
echo "=== Total Memory on Worker1 ==="
multipass exec k8s-worker1 -- cat /proc/meminfo | head -5
echo ""
echo "=== Total Memory on Worker2 ==="
multipass exec k8s-worker2 -- cat /proc/meminfo | head -5
echo ""
echo "=== Memory Usage on Worker1 ==="
multipass exec k8s-worker1 -- free -h
echo ""
echo "=== Memory Usage on Worker2 ==="
multipass exec k8s-worker2 -- free -h
echo ""
echo "=== Swap Status on Worker1 (should be disabled for k8s) ==="
multipass exec k8s-worker1 -- swapon --show 2>/dev/null || echo "No swap configured"
echo ""
echo "=== Swap Status on Worker2 (should be disabled for k8s) ==="
multipass exec k8s-worker2 -- swapon --show 2>/dev/null || echo "No swap configured"
echo ""
echo "=== OOM Events on Worker1 ==="
multipass exec k8s-worker1 -- sudo dmesg | grep -i "oom\|out of memory" || echo "No OOM events"
echo ""
echo "=== OOM Events on Worker2 ==="
multipass exec k8s-worker2 -- sudo dmesg | grep -i "oom\|out of memory" || echo "No OOM events"
echo ""
echo "=== Kernel Messages on Worker1 ==="
multipass exec k8s-worker1 -- sudo dmesg | tail -20
echo ""
echo "=== Kernel Messages on Worker2 ==="
multipass exec k8s-worker2 -- sudo dmesg | tail -20
echo ""
echo "=== Systemd Failed Units on Worker1 ==="
multipass exec k8s-worker1 -- sudo systemctl --failed
echo ""
echo "=== Systemd Failed Units on Worker2 ==="
multipass exec k8s-worker2 -- sudo systemctl --failed
echo ""
echo "=== kubelet Status on Worker1 ==="
multipass exec k8s-worker1 -- sudo systemctl status kubelet --no-pager
echo ""
echo "=== kubelet Status on Worker2 ==="
multipass exec k8s-worker2 -- sudo systemctl status kubelet --no-pager
echo ""
echo "=== containerd Status on Worker1 ==="
multipass exec k8s-worker1 -- sudo systemctl status containerd --no-pager
echo ""
echo "=== containerd Status on Worker2 ==="
multipass exec k8s-worker2 -- sudo systemctl status containerd --no-pager
echo ""
echo "=== Running Containers on Worker1 ==="
multipass exec k8s-worker1 -- sudo crictl ps 2>/dev/null || echo "crictl not available"
echo ""
echo "=== Running Containers on Worker2 ==="
multipass exec k8s-worker2 -- sudo crictl ps 2>/dev/null || echo "crictl not available"
echo ""
echo "=== Container Images on Worker1 ==="
multipass exec k8s-worker1 -- sudo crictl images 2>/dev/null || echo "crictl not available"
echo ""
echo "=== Container Images on Worker2 ==="
multipass exec k8s-worker2 -- sudo crictl images 2>/dev/null || echo "crictl not available"
echo ""
echo "=== Pod Status ==="
kubectl get pods -n demo -o wide
echo ""
echo "=== Pod Phase ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Phase: "}{.status.phase}{"\n"}{end}'
echo ""
echo "=== Container States ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.containerStatuses[*]}{"  Container: "}{.name}{" State: "}{.state}{"\n"}{end}{end}'
echo ""
echo "=== Pod Restart Count ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Restarts: "}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
echo ""
echo "=== Pod Age ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Started: "}{.status.startTime}{"\n"}{end}'
echo ""
echo "=== Backend Readiness ==="
kubectl get pods -n demo -l app=backend \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Ready: "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
echo ""
echo "=== Pod Descriptions ==="
kubectl describe pods -n demo
echo ""
echo "=== Deployment Status ==="
kubectl get deployments -n demo -o wide
echo ""
echo "=== Deployment Rollout Status ==="
kubectl rollout status deployment -n demo 2>/dev/null || echo "No deployments found"
echo ""
echo "=== Deployment Rollout History ==="
kubectl rollout history deployment -n demo 2>/dev/null || echo "No deployment history found"
echo ""
echo "=== ReplicaSets ==="
kubectl get replicasets -n demo
echo ""
echo "=== ReplicaSet Details ==="
kubectl describe replicasets -n demo
echo ""
echo "=== HorizontalPodAutoscalers ==="
kubectl get hpa -n demo 2>/dev/null || echo "No HPAs found"
echo ""
echo "=== Pod Resource Requests and Limits ==="
kubectl describe pods -n demo | grep -A6 "Requests:\|Limits:"
echo ""
echo "=== Resource Usage (Nodes) ==="
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo ""
echo "=== Resource Usage (Pods) ==="
kubectl top pods -n demo 2>/dev/null || echo "Metrics server not available"
echo ""
# ============================================================
# 3. STORAGE
# ============================================================
echo "========================================"
echo "=== STORAGE DIAGNOSTICS ==="
echo "========================================"
echo "=== Disk Usage on Worker1 ==="
multipass exec k8s-worker1 -- df -h
echo ""
echo "=== Disk Usage on Worker2 ==="
multipass exec k8s-worker2 -- df -h
echo ""
echo "=== Inodes Usage on Worker1 ==="
multipass exec k8s-worker1 -- df -i
echo ""
echo "=== Inodes Usage on Worker2 ==="
multipass exec k8s-worker2 -- df -i
echo ""
echo "=== StorageClasses ==="
kubectl get storageclasses 2>/dev/null || echo "No storage classes found"
echo ""
echo "=== PersistentVolumes ==="
kubectl get pv 2>/dev/null || echo "No PVs found"
echo ""
echo "=== PersistentVolume Details ==="
kubectl describe pv 2>/dev/null || echo "No PVs found"
echo ""
echo "=== PersistentVolumeClaims ==="
kubectl get pvc -n demo 2>/dev/null || echo "No PVCs found"
echo ""
echo "=== PersistentVolumeClaim Details ==="
kubectl describe pvc -n demo 2>/dev/null || echo "No PVCs found"
echo ""
echo "=== Volumes in Use by Pods ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\nVolumes: "}{.spec.volumes}{"\n"}{end}'
echo ""
echo "=== Disk Usage Inside Backend Pod ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- df -h 2>/dev/null || echo "Could not check disk in backend pod"
else
  echo "No backend pod found"
fi
echo ""
echo "=== Disk Usage Inside Redis Pod ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- df -h 2>/dev/null || echo "Could not check disk in redis pod"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Memory Usage ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info memory 2>/dev/null || echo "Could not get Redis memory info"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Key Count ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli dbsize 2>/dev/null || echo "Could not get Redis key count"
else
  echo "No redis pod found"
fi
echo ""
# ============================================================
# 4. NETWORK
# ============================================================
echo "========================================"
echo "=== NETWORK DIAGNOSTICS              ==="
echo "========================================"
echo "=== Mac Network Interfaces ==="
ifconfig | grep -E "^[a-z]|inet " | grep -v "inet6"
echo ""
echo "=== Mac Routing Table (full) ==="
netstat -rn
echo ""
echo "=== Route to VM Subnet ==="
netstat -rn | grep "192.168.2"
echo ""
echo "=== Mac Firewall Status ==="
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null
echo ""
echo "=== Mac Firewall Rules (pf) ==="
sudo pfctl -sr 2>/dev/null | head -30 || echo "pfctl not available or no rules"
echo ""
echo "=== Mac Open Ports ==="
sudo lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | head -30
echo ""
echo "=== Mac DNS Resolution ==="
nslookup kubernetes.default 2>/dev/null || echo "DNS lookup failed"
echo ""
echo "=== Ping Test to Worker1 ==="
ping -c 2 192.168.2.65
echo ""
echo "=== Ping Test to Worker2 ==="
ping -c 2 192.168.2.66
echo ""
echo "=== Port Test Worker1:30500 ==="
nc -zv 192.168.2.65 30500 2>&1
echo ""
echo "=== Port Test Worker2:30500 ==="
nc -zv 192.168.2.66 30500 2>&1
echo ""
echo "=== Network Interfaces on Worker1 ==="
multipass exec k8s-worker1 -- ip addr show
echo ""
echo "=== Network Interfaces on Worker2 ==="
multipass exec k8s-worker2 -- ip addr show
echo ""
echo "=== Routing Table on Worker1 ==="
multipass exec k8s-worker1 -- ip route show
echo ""
echo "=== Routing Table on Worker2 ==="
multipass exec k8s-worker2 -- ip route show
echo ""
#echo "=== ARP Table on Worker1 ==="
#multipass exec k8s-worker1 -- arp -n
#echo ""
#echo "=== ARP Table on Worker2 ==="
#multipass exec k8s-worker2 -- arp -n
#echo ""
echo "=== Open Ports on Worker1 ==="
multipass exec k8s-worker1 -- sudo ss -tulnp
echo ""
echo "=== Open Ports on Worker2 ==="
multipass exec k8s-worker2 -- sudo ss -tulnp
echo ""
#echo "=== iptables Rules on Worker1 ==="
#multipass exec k8s-worker1 -- sudo iptables -L -n --line-numbers | head -60
#echo ""
#echo "=== iptables Rules on Worker2 ==="
#multipass exec k8s-worker2 -- sudo iptables -L -n --line-numbers | head -60
#echo ""
#echo "=== iptables NAT Rules on Worker1 ==="
#multipass exec k8s-worker1 -- sudo iptables -t nat -L -n | head -60
#echo ""
#echo "=== iptables NAT Rules on Worker2 ==="
#multipass exec k8s-worker2 -- sudo iptables -t nat -L -n | head -60
#echo ""
echo "=== CNI Config on Worker1 ==="
multipass exec k8s-worker1 -- cat /etc/cni/net.d/*.conf 2>/dev/null || echo "No CNI config found"
echo ""
echo "=== CNI Config on Worker2 ==="
multipass exec k8s-worker2 -- cat /etc/cni/net.d/*.conf 2>/dev/null || echo "No CNI config found"
echo ""
echo "=== CNI Plugins on Worker1 ==="
multipass exec k8s-worker1 -- ls /opt/cni/bin/ 2>/dev/null || echo "No CNI plugins found"
echo ""
echo "=== CNI Plugins on Worker2 ==="
multipass exec k8s-worker2 -- ls /opt/cni/bin/ 2>/dev/null || echo "No CNI plugins found"
echo ""
echo "=== Kubernetes Services ==="
kubectl get services -n demo -o wide
echo ""
echo "=== Service Endpoints ==="
kubectl get endpoints -n demo
echo ""
echo "=== Endpoint Details ==="
kubectl describe endpoints -n demo
echo ""
echo "=== NodePort Services ==="
kubectl get svc -n demo \
  -o jsonpath='{range .items[?(@.spec.type=="NodePort")]}{.metadata.name}{" NodePort: "}{.spec.ports[*].nodePort}{"\n"}{end}'
echo ""
echo "=== ClusterIP Services ==="
kubectl get svc -n demo \
  -o jsonpath='{range .items[?(@.spec.type=="ClusterIP")]}{.metadata.name}{" ClusterIP: "}{.spec.clusterIP}{"\n"}{end}'
echo ""
echo "=== Ingress Resources ==="
kubectl get ingress -n demo 2>/dev/null || echo "No ingress resources found"
echo ""
echo "=== Ingress Details ==="
kubectl describe ingress -n demo 2>/dev/null || echo "No ingress resources found"
echo ""
#echo "=== kube-proxy Status on Worker1 ==="
#multipass exec k8s-worker1 -- sudo systemctl status kube-proxy --no-pager 2>/dev/null \
#  || echo "kube-proxy not running as systemd service"
#echo ""
#echo "=== kube-proxy Status on Worker2 ==="
#multipass exec k8s-worker2 -- sudo systemctl status kube-proxy --no-pager 2>/dev/null \
#  || echo "kube-proxy not running as systemd service"
#echo ""
echo "=== kube-proxy Pod Logs ==="
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=20 2>/dev/null \
  || echo "No kube-proxy logs found"
echo ""
echo "=== CoreDNS Pod Status ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns
echo ""
echo "=== CoreDNS Logs ==="
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20 2>/dev/null \
  || echo "No CoreDNS logs found"
echo ""
echo "=== DNS Resolution from Backend Pod ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- nslookup kubernetes.default 2>/dev/null \
    || echo "DNS resolution failed"
else
  echo "No backend pod found"
fi
echo ""
echo "=== DNS Resolution for Redis Service from Backend Pod ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- nslookup redis 2>/dev/null \
    || echo "Redis DNS resolution failed"
else
  echo "No backend pod found"
fi
echo ""
echo "=== Pod-to-Pod Connectivity (Backend to Redis) ==="
if [ -n "$BACKEND_POD" ] && [ -n "$REDIS_IP" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- ping -c 2 "$REDIS_IP" 2>/dev/null \
    || echo "Ping not available"
else
  echo "Backend or Redis pod not found"
fi
echo ""
echo "=== Pod-to-Service Connectivity (Backend to Redis Service) ==="
if [ -n "$BACKEND_POD" ] && [ -n "$REDIS_SVC_IP" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- nc -zv "$REDIS_SVC_IP" 6379 2>/dev/null \
    || echo "Could not test Redis service connectivity"
else
  echo "Backend pod or Redis service IP not found"
fi
echo ""
echo "=== NetworkPolicies ==="
kubectl get networkpolicies -n demo 2>/dev/null || echo "No NetworkPolicies found"
echo ""
echo "=== NetworkPolicy Details ==="
kubectl describe networkpolicies -n demo 2>/dev/null || echo "No NetworkPolicies found"
echo ""
# ============================================================
# 5. SECURITY
# ============================================================
echo "========================================"
echo "=== SECURITY DIAGNOSTICS ==="
echo "========================================"
echo "=== ServiceAccounts ==="
kubectl get serviceaccounts -n demo
echo ""
echo "=== ServiceAccount Details ==="
kubectl describe serviceaccounts -n demo
echo ""
echo "=== RBAC - RoleBindings ==="
kubectl get rolebindings -n demo 2>/dev/null || echo "No RoleBindings found"
echo ""
echo "=== RBAC - RoleBinding Details ==="
kubectl describe rolebindings -n demo 2>/dev/null || echo "No RoleBindings found"
echo ""
echo "=== RBAC - ClusterRoleBindings ==="
kubectl get clusterrolebindings 2>/dev/null | head -30
echo ""
echo "=== RBAC - Roles ==="
kubectl get roles -n demo 2>/dev/null || echo "No Roles found"
echo ""
echo "=== RBAC - ClusterRoles ==="
kubectl get clusterroles 2>/dev/null | head -30
echo ""
echo "=== Pod Security Context ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\nSecurityContext: "}{.spec.securityContext}{"\n"}{end}'
echo ""
echo "=== Container Security Context ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}{"  Container: "}{.name}{" SecurityContext: "}{.securityContext}{"\n"}{end}{end}'
echo ""
echo "=== Privileged Containers ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}{"  Container: "}{.name}{" Privileged: "}{.securityContext.privileged}{"\n"}{end}{end}'
echo ""
echo "=== Secrets ==="
kubectl get secrets -n demo
echo ""
echo "=== Secret Types ==="
kubectl get secrets -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Type: "}{.type}{"\n"}{end}'
echo ""
echo "=== ConfigMaps ==="
kubectl get configmaps -n demo
echo ""
echo "=== ConfigMap Details ==="
kubectl describe configmaps -n demo
echo ""
echo "=== Pod Service Account Tokens ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" ServiceAccount: "}{.spec.serviceAccountName}{"\n"}{end}'
echo ""
echo "=== Admission Controllers ==="
kubectl api-versions | grep admission 2>/dev/null \
  || echo "No admission controllers visible via api-versions"
echo ""
echo "=== PodDisruptionBudgets ==="
kubectl get pdb -n demo 2>/dev/null || echo "No PodDisruptionBudgets found"
echo ""
echo "=== ResourceQuotas ==="
kubectl get resourcequota -n demo 2>/dev/null || echo "No ResourceQuotas found"
echo ""
echo "=== LimitRanges ==="
kubectl get limitrange -n demo 2>/dev/null || echo "No LimitRanges found"
echo ""
echo "=== TLS Certificates (Kubernetes PKI) ==="
multipass exec k8s-worker1 -- sudo ls /etc/kubernetes/pki/ 2>/dev/null \
  || echo "PKI directory not accessible"
echo ""
echo "=== kubelet Certificate Expiry on Worker1 ==="
multipass exec k8s-worker1 -- sudo openssl x509 \
  -in /var/lib/kubelet/pki/kubelet-client-current.pem \
  -noout -dates 2>/dev/null \
  || echo "Could not read kubelet cert on Worker1"
echo ""
echo "=== kubelet Certificate Expiry on Worker2 ==="
multipass exec k8s-worker2 -- sudo openssl x509 \
  -in /var/lib/kubelet/pki/kubelet-client-current.pem \
  -noout -dates 2>/dev/null \
  || echo "Could not read kubelet cert on Worker2"
echo ""
# ============================================================
# 6. APPLICATION-LEVEL
# ============================================================
echo "========================================"
echo "=== APPLICATION-LEVEL DIAGNOSTICS ==="
echo "========================================"
echo "=== Backend Pod Logs ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl logs -n demo "$BACKEND_POD" --tail=50
else
  echo "No backend pod found"
fi
echo ""
echo "=== Backend Pod Previous Logs (if restarted) ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl logs -n demo "$BACKEND_POD" --previous --tail=50 2>/dev/null \
    || echo "No previous logs"
else
  echo "No backend pod found"
fi
echo ""
echo "=== Redis Pod Logs ==="
if [ -n "$REDIS_POD" ]; then
  kubectl logs -n demo "$REDIS_POD" --tail=50
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Pod Previous Logs (if restarted) ==="
if [ -n "$REDIS_POD" ]; then
  kubectl logs -n demo "$REDIS_POD" --previous --tail=50 2>/dev/null \
    || echo "No previous logs"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Frontend Pod Logs ==="
if [ -n "$FRONTEND_POD" ]; then
  kubectl logs -n demo "$FRONTEND_POD" --tail=50
else
  echo "No frontend pod found"
fi
echo ""
echo "=== All Pod Logs in Demo Namespace ==="
for pod in $(kubectl get pods -n demo -o jsonpath='{.items[*].metadata.name}'); do
  echo "--- Logs for $pod ---"
  kubectl logs -n demo "$pod" --tail=20 2>/dev/null || echo "Could not retrieve logs"
  echo ""
done
echo ""
echo "=== Environment Variables in Backend Pod ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- env 2>/dev/null \
    || echo "Could not retrieve env vars"
else
  echo "No backend pod found"
fi
echo ""
echo "=== Environment Variables in Redis Pod ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- env 2>/dev/null \
    || echo "Could not retrieve env vars"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Backend App Health Check (HTTP) ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- \
    curl -s http://localhost:5000/health 2>/dev/null \
    || echo "Health check failed or endpoint not available"
else
  echo "No backend pod found"
fi
echo ""
echo "=== Backend App Root Endpoint ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- \
    curl -s http://localhost:5000/ 2>/dev/null \
    || echo "Root endpoint check failed"
else
  echo "No backend pod found"
fi
echo ""
echo "=== Redis Ping ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli ping \
  2>/dev/null || echo "Redis ping failed"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Info ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info 2>/dev/null \
    || echo "Could not get Redis info"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Replication Info ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info replication 2>/dev/null \
    || echo "Could not get Redis replication info"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Slow Log ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli slowlog get 10 2>/dev/null \
    || echo "Could not get Redis slow log"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Backend Service NodePort HTTP Test (Worker1) ==="
curl -s --max-time 5 http://192.168.2.65:30500/health 2>/dev/null \
  || echo "NodePort health check failed on Worker1"
echo ""
echo "=== Backend Service NodePort HTTP Test (Worker2) ==="
curl -s --max-time 5 http://192.168.2.66:30500/health 2>/dev/null \
  || echo "NodePort health check failed on Worker2"
echo ""
echo "=== Backend Service NodePort Root Test (Worker1) ==="
curl -s --max-time 5 http://192.168.2.65:30500/ 2>/dev/null \
  || echo "NodePort root check failed on Worker1"
echo ""
echo "=== Events in Demo Namespace ==="
kubectl get events -n demo --sort-by='.lastTimestamp'
echo ""
echo "=== Warning Events in Demo Namespace ==="
kubectl get events -n demo --field-selector type=Warning --sort-by='.lastTimestamp'
echo ""
echo "=== Events in kube-system Namespace ==="
kubectl get events -n kube-system --sort-by='.lastTimestamp' | tail -20
echo ""
# ============================================================
# 7. TIMING / LATENCY
# ============================================================
echo "========================================"
echo "=== TIMING / LATENCY DIAGNOSTICS ==="
echo "========================================"
echo "=== Mac System Clock ==="
date
echo ""
echo "=== System Clock on Worker1 ==="
multipass exec k8s-worker1 -- date
echo ""
echo "=== System Clock on Worker2 ==="
multipass exec k8s-worker2 -- date
echo ""
echo "=== Clock Skew Check (Worker1 vs Mac) ==="
MAC_TIME=$(date +%s)
WORKER1_TIME=$(multipass exec k8s-worker1 -- date +%s)
echo "Mac epoch:     $MAC_TIME"
echo "Worker1 epoch: $WORKER1_TIME"
echo "Skew (seconds): $((WORKER1_TIME - MAC_TIME))"
echo ""
echo "=== Clock Skew Check (Worker2 vs Mac) ==="
MAC_TIME=$(date +%s)
WORKER2_TIME=$(multipass exec k8s-worker2 -- date +%s)
echo "Mac epoch:     $MAC_TIME"
echo "Worker2 epoch: $WORKER2_TIME"
echo "Skew (seconds): $((WORKER2_TIME - MAC_TIME))"
echo ""
echo "=== NTP Status on Worker1 ==="
multipass exec k8s-worker1 -- timedatectl status 2>/dev/null \
  || echo "timedatectl not available"
echo ""
echo "=== NTP Status on Worker2 ==="
multipass exec k8s-worker2 -- timedatectl status 2>/dev/null \
  || echo "timedatectl not available"
echo ""
echo "=== NTP Sync Service on Worker1 ==="
multipass exec k8s-worker1 -- sudo systemctl status systemd-timesyncd --no-pager 2>/dev/null \
  || echo "systemd-timesyncd not available"
echo ""
echo "=== NTP Sync Service on Worker2 ==="
multipass exec k8s-worker2 -- sudo systemctl status systemd-timesyncd --no-pager 2>/dev/null \
  || echo "systemd-timesyncd not available"
echo ""
echo "=== Latency: Mac to Worker1 ==="
ping -c 5 192.168.2.65 | tail -2
echo ""
echo "=== Latency: Mac to Worker2 ==="
ping -c 5 192.168.2.66 | tail -2
echo ""
echo "=== Latency: Worker1 to Worker2 ==="
multipass exec k8s-worker1 -- ping -c 5 192.168.2.66 | tail -2
echo ""
echo "=== Latency: Worker2 to Worker1 ==="
multipass exec k8s-worker2 -- ping -c 5 192.168.2.65 | tail -2
echo ""
echo "=== Traceroute: Mac to Worker1 ==="
traceroute -m 10 192.168.2.65 2>/dev/null || echo "traceroute not available"
echo ""
echo "=== Traceroute: Mac to Worker2 ==="
traceroute -m 10 192.168.2.66 2>/dev/null || echo "traceroute not available"
echo ""
echo "=== API Server Response Time ==="
time kubectl get nodes > /dev/null 2>&1
echo ""
echo "=== Backend Health Endpoint Response Time (Worker1) ==="
curl -o /dev/null -s -w "HTTP Code: %{http_code}  Time: %{time_total}s\n" \
  --max-time 5 http://192.168.2.65:30500/health 2>/dev/null \
  || echo "Could not measure response time on Worker1"
echo ""
echo "=== Backend Health Endpoint Response Time (Worker2) ==="
curl -o /dev/null -s -w "HTTP Code: %{http_code}  Time: %{time_total}s\n" \
  --max-time 5 http://192.168.2.66:30500/health 2>/dev/null \
  || echo "Could not measure response time on Worker2"
echo ""
echo "=== Backend Root Endpoint Response Time (Worker1) ==="
curl -o /dev/null -s -w "HTTP Code: %{http_code}  Time: %{time_total}s\n" \
  --max-time 5 http://192.168.2.65:30500/ 2>/dev/null \
  || echo "Could not measure response time on Worker1"
echo ""
echo "=== Redis Intrinsic Latency (1 sec sample) ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli --intrinsic-latency 1 2>/dev/null \
    || echo "Could not measure Redis intrinsic latency"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Command Latency (5 sec sample) ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- \
    timeout 5 redis-cli --latency-history -i 1 2>/dev/null \
    || echo "Could not measure Redis command latency"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Pod Scheduling Latency (creation to running) ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n  Created:    "}{.metadata.creationTimestamp}{"\n  Started:    "}{.status.startTime}{"\n  Ready at:   "}{.status.conditions[?(@.type=="Ready")].lastTransitionTime}{"\n"}{end}'
echo ""
echo "=== kubelet Sync Latency on Worker1 ==="
multipass exec k8s-worker1 -- sudo journalctl -u kubelet --no-pager --since "5 minutes ago" \
  | grep -i "latency\|slow\|timeout" | tail -20 \
  || echo "No latency events in kubelet logs on Worker1"
echo ""
echo "=== kubelet Sync Latency on Worker2 ==="
multipass exec k8s-worker2 -- sudo journalctl -u kubelet --no-pager --since "5 minutes ago" \
  | grep -i "latency\|slow\|timeout" | tail -20 \
  || echo "No latency events in kubelet logs on Worker2"
echo ""
# ============================================================
# 8. ERROR RATES
# ============================================================
echo "========================================"
echo "=== ERROR RATE DIAGNOSTICS ==="
echo "========================================"
echo "=== Pod Restart Counts ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Restarts: "}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
echo ""
echo "=== Pods Not in Running State ==="
kubectl get pods -n demo --field-selector=status.phase!=Running 2>/dev/null \
  || echo "All pods running"
echo ""
echo "=== CrashLoopBackOff / Error Pods ==="
kubectl get pods -n demo \
  | grep -iE "CrashLoop|Error|OOMKilled|Evicted|Pending|Terminating" \
  || echo "No unhealthy pods detected"
echo ""
echo "=== OOMKilled Containers ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.containerStatuses[*]}{"  Container: "}{.name}{" LastState: "}{.lastState}{"\n"}{end}{end}' \
  | grep -A2 "OOMKilled" \
  || echo "No OOMKilled containers found"
echo ""
echo "=== Warning Events (all namespaces) ==="
kubectl get events --all-namespaces \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -30
echo ""
echo "=== Failed Events in Demo Namespace ==="
kubectl get events -n demo \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp'
echo ""
echo "=== kubelet Errors on Worker1 ==="
multipass exec k8s-worker1 -- sudo journalctl -u kubelet --no-pager --since "30 minutes ago" \
  | grep -iE "error|fail|warn|panic|fatal" | tail -30 \
  || echo "No kubelet errors found on Worker1"
echo ""
echo "=== kubelet Errors on Worker2 ==="
multipass exec k8s-worker2 -- sudo journalctl -u kubelet --no-pager --since "30 minutes ago" \
  | grep -iE "error|fail|warn|panic|fatal" | tail -30 \
  || echo "No kubelet errors found on Worker2"
echo ""
echo "=== containerd Errors on Worker1 ==="
multipass exec k8s-worker1 -- sudo journalctl -u containerd --no-pager --since "30 minutes ago" \
  | grep -iE "error|fail|warn|panic|fatal" | tail -30 \
  || echo "No containerd errors found on Worker1"
echo ""
echo "=== containerd Errors on Worker2 ==="
multipass exec k8s-worker2 -- sudo journalctl -u containerd --no-pager --since "30 minutes ago" \
  | grep -iE "error|fail|warn|panic|fatal" | tail -30 \
  || echo "No containerd errors found on Worker2"
echo ""
echo "=== kube-proxy Errors ==="
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50 2>/dev/null \
  | grep -iE "error|fail|warn" \
  || echo "No kube-proxy errors found"
echo ""
echo "=== CoreDNS Errors ==="
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 2>/dev/null \
  | grep -iE "error|fail|warn|SERVFAIL|REFUSED" \
  || echo "No CoreDNS errors found"
echo ""
echo "=== API Server Errors ==="
kubectl logs -n kube-system -l component=kube-apiserver --tail=50 2>/dev/null \
  | grep -iE "error|fail|warn|panic" | tail -20 \
  || echo "No API server errors found"
echo ""
echo "=== etcd Errors ==="
kubectl logs -n kube-system -l component=etcd --tail=50 2>/dev/null \
  | grep -iE "error|fail|warn|panic|slow" | tail -20 \
  || echo "No etcd errors found"
echo ""
echo "=== Backend Pod Error Logs ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl logs -n demo "$BACKEND_POD" --tail=100 2>/dev/null \
    | grep -iE "error|exception|fail|warn|traceback|critical" \
    || echo "No errors in backend logs"
else
  echo "No backend pod found"
fi
echo ""
echo "=== Redis Error Logs ==="
if [ -n "$REDIS_POD" ]; then
  kubectl logs -n demo "$REDIS_POD" --tail=100 2>/dev/null \
    | grep -iE "error|warn|fail|panic" \
    || echo "No errors in Redis logs"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Kernel Errors on Worker1 ==="
multipass exec k8s-worker1 -- sudo dmesg \
  | grep -iE "error|fail|warn|call trace|bug:" | tail -20 \
  || echo "No kernel errors found on Worker1"
echo ""
echo "=== Kernel Errors on Worker2 ==="
multipass exec k8s-worker2 -- sudo dmesg \
  | grep -iE "error|fail|warn|call trace|bug:" | tail -20 \
  || echo "No kernel errors found on Worker2"
echo ""
echo "=== Network Errors on Worker1 ==="
multipass exec k8s-worker1 -- ip -s link show \
  | grep -A4 "errors\|dropped\|missed" \
  || echo "No network error counters found on Worker1"
echo ""
echo "=== Network Errors on Worker2 ==="
multipass exec k8s-worker2 -- ip -s link show \
  | grep -A4 "errors\|dropped\|missed" \
  || echo "No network error counters found on Worker2"
echo ""
echo "=== TCP Socket Stats on Worker1 ==="
multipass exec k8s-worker1 -- ss -s 2>/dev/null \
  || echo "Could not get socket stats on Worker1"
echo ""
echo "=== TCP Socket Stats on Worker2 ==="
multipass exec k8s-worker2 -- ss -s 2>/dev/null \
  || echo "Could not get socket stats on Worker2"
echo ""
echo "=== Redis Error Count ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info stats 2>/dev/null \
    | grep -E "rejected_connections|keyspace_misses|keyspace_hits" \
    || echo "Could not get Redis error stats"
else
  echo "No redis pod found"
fi
echo ""
# ============================================================
# 9. THROUGHPUT
# ============================================================
echo "========================================"
echo "=== THROUGHPUT DIAGNOSTICS ==="
echo "========================================"
echo "=== Network Interface Stats on Worker1 ==="
multipass exec k8s-worker1 -- cat /proc/net/dev
echo ""
echo "=== Network Interface Stats on Worker2 ==="
multipass exec k8s-worker2 -- cat /proc/net/dev
echo ""
echo "=== Network Throughput Snapshot on Worker1 (2 sec sample) ==="
multipass exec k8s-worker1 -- bash -c '
  R1=$(cat /proc/net/dev | grep eth0 | awk "{print \$2,\$10}")
  sleep 2
  R2=$(cat /proc/net/dev | grep eth0 | awk "{print \$2,\$10}")
  RX1=$(echo $R1 | awk "{print \$1}")
  TX1=$(echo $R1 | awk "{print \$2}")
  RX2=$(echo $R2 | awk "{print \$1}")
  TX2=$(echo $R2 | awk "{print \$2}")
  echo "RX: $(( (RX2 - RX1) / 2 )) bytes/sec"
  echo "TX: $(( (TX2 - TX1) / 2 )) bytes/sec"
' 2>/dev/null || echo "Could not measure network throughput on Worker1"
echo ""
echo "=== Network Throughput Snapshot on Worker2 (2 sec sample) ==="
multipass exec k8s-worker2 -- bash -c '
  R1=$(cat /proc/net/dev | grep eth0 | awk "{print \$2,\$10}")
  sleep 2
  R2=$(cat /proc/net/dev | grep eth0 | awk "{print \$2,\$10}")
  RX1=$(echo $R1 | awk "{print \$1}")
  TX1=$(echo $R1 | awk "{print \$2}")
  RX2=$(echo $R2 | awk "{print \$1}")
  TX2=$(echo $R2 | awk "{print \$2}")
  echo "RX: $(( (RX2 - RX1) / 2 )) bytes/sec"
  echo "TX: $(( (TX2 - TX1) / 2 )) bytes/sec"
' 2>/dev/null || echo "Could not measure network throughput on Worker2"
echo ""
echo "=== Disk I/O Stats on Worker1 ==="
multipass exec k8s-worker1 -- iostat -x 1 2 2>/dev/null || \
  multipass exec k8s-worker1 -- cat /proc/diskstats | head -20
echo ""
echo "=== Disk I/O Stats on Worker2 ==="
multipass exec k8s-worker2 -- iostat -x 1 2 2>/dev/null || \
  multipass exec k8s-worker2 -- cat /proc/diskstats | head -20
echo ""
echo "=== CPU Throughput (vmstat) on Worker1 ==="
multipass exec k8s-worker1 -- vmstat 1 3 2>/dev/null || echo "vmstat not available on Worker1"
echo ""
echo "=== CPU Throughput (vmstat) on Worker2 ==="
multipass exec k8s-worker2 -- vmstat 1 3 2>/dev/null || echo "vmstat not available on Worker2"
echo ""
echo "=== Process Count on Worker1 ==="
multipass exec k8s-worker1 -- ps aux --no-headers | wc -l
echo ""
echo "=== Process Count on Worker2 ==="
multipass exec k8s-worker2 -- ps aux --no-headers | wc -l
echo ""
#echo "=== Top Processes by CPU on Worker1 ==="
#multipass exec k8s-worker1 -- ps aux --sort=-%cpu | head -10
#echo ""
#echo "=== Top Processes by CPU on Worker2 ==="
#multipass exec k8s-worker2 -- ps aux --sort=-%cpu | head -10
#echo ""
#echo "=== Top Processes by Memory on Worker1 ==="
#multipass exec k8s-worker1 -- ps aux --sort=-%mem | head -10
#echo ""
#echo "=== Top Processes by Memory on Worker2 ==="
#multipass exec k8s-worker2 -- ps aux --sort=-%mem | head -10
#echo ""
echo "=== Redis Throughput Stats ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info stats 2>/dev/null \
    | grep -E "total_commands_processed|instantaneous_ops_per_sec|total_net_input_bytes|total_net_output_bytes|instantaneous_input_kbps|instantaneous_output_kbps" \
    || echo "Could not get Redis throughput stats"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Connected Clients ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info clients 2>/dev/null \
    | grep -E "connected_clients|blocked_clients|tracking_clients" \
    || echo "Could not get Redis client stats"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Redis Persistence Stats ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info persistence 2>/dev/null \
    || echo "Could not get Redis persistence stats"
else
  echo "No redis pod found"
fi
echo ""
#echo "=== Kubernetes API Request Rate (audit log sample) ==="
#multipass exec k8s-worker1 -- sudo find /var/log/kubernetes -name "*.log" 2>/dev/null \
#  | xargs sudo tail -n 20 2>/dev/null || echo "No Kubernetes audit logs found"
echo ""
echo "=== kubelet Request Throughput on Worker1 ==="
multipass exec k8s-worker1 -- sudo journalctl -u kubelet --no-pager --since "5 minutes ago" \
  | grep -i "request\|handler\|verb" | tail -20 || echo "No kubelet request logs found on Worker1"
echo ""
echo "=== kubelet Request Throughput on Worker2 ==="
multipass exec k8s-worker2 -- sudo journalctl -u kubelet --no-pager --since "5 minutes ago" \
  | grep -i "request\|handler\|verb" | tail -20 || echo "No kubelet request logs found on Worker2"
echo ""
echo "=== containerd Task Throughput on Worker1 ==="
multipass exec k8s-worker1 -- sudo journalctl -u containerd --no-pager --since "5 minutes ago" \
  | tail -20 || echo "No containerd logs found on Worker1"
echo ""
echo "=== containerd Task Throughput on Worker2 ==="
multipass exec k8s-worker2 -- sudo journalctl -u containerd --no-pager --since "5 minutes ago" \
  | tail -20 || echo "No containerd logs found on Worker2"
echo ""
echo "=== Active TCP Connections on Worker1 ==="
multipass exec k8s-worker1 -- ss -tn state established | wc -l
echo ""
echo "=== Active TCP Connections on Worker2 ==="
multipass exec k8s-worker2 -- ss -tn state established | wc -l
echo ""
echo "=== TCP Connection States on Worker1 ==="
multipass exec k8s-worker1 -- ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn
echo ""
echo "=== TCP Connection States on Worker2 ==="
multipass exec k8s-worker2 -- ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn
echo ""
# ============================================================
# 10. SUMMARY
# ============================================================
echo "========================================"
echo "=== DIAGNOSTIC SUMMARY ==="
echo "========================================"
echo "=== Timestamp ==="
date
echo ""
echo "=== Cluster Context ==="
kubectl config current-context
echo ""
echo "=== Node Summary ==="
kubectl get nodes -o wide
echo ""
echo "=== Node Resource Pressure ==="
kubectl describe nodes | grep -E "DiskPressure|MemoryPressure|PIDPressure|Ready"
echo ""
echo "=== Node Resource Usage ==="
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo ""
echo "=== Pod Summary (demo namespace) ==="
kubectl get pods -n demo -o wide
echo ""
echo "=== Pod Resource Usage ==="
kubectl top pods -n demo 2>/dev/null || echo "Metrics server not available"
echo ""
echo "=== Pod Restart Summary ==="
kubectl get pods -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Restarts: "}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
echo ""
echo "=== Pods NOT Running ==="
kubectl get pods -n demo --field-selector=status.phase!=Running 2>/dev/null \
  || echo "All pods are Running"
echo ""
echo "=== CrashLoopBackOff / Error Pods ==="
kubectl get pods -n demo \
  | grep -iE "CrashLoop|Error|OOMKilled|Evicted|Pending|Terminating" \
  || echo "No unhealthy pods detected"
echo ""
echo "=== Service Summary ==="
kubectl get services -n demo -o wide
echo ""
echo "=== Endpoint Health ==="
kubectl get endpoints -n demo
echo ""
echo "=== PVC Summary ==="
kubectl get pvc -n demo 2>/dev/null || echo "No PVCs found"
echo ""
echo "=== Warning Events Summary ==="
kubectl get events -n demo \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -20
echo ""
echo "=== kube-system Pod Health ==="
kubectl get pods -n kube-system -o wide
echo ""
echo "=== etcd Health ==="
kubectl get pods -n kube-system | grep etcd
echo ""
echo "=== CoreDNS Health ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns
echo ""
echo "=== Worker1 Vital Signs ==="
echo "-- Uptime --"
multipass exec k8s-worker1 -- uptime
echo "-- Memory --"
multipass exec k8s-worker1 -- free -h
echo "-- Disk --"
multipass exec k8s-worker1 -- df -h /
echo "-- kubelet --"
multipass exec k8s-worker1 -- sudo systemctl is-active kubelet
echo "-- containerd --"
multipass exec k8s-worker1 -- sudo systemctl is-active containerd
echo ""
echo "=== Worker2 Vital Signs ==="
echo "-- Uptime --"
multipass exec k8s-worker2 -- uptime
echo "-- Memory --"
multipass exec k8s-worker2 -- free -h
echo "-- Disk --"
multipass exec k8s-worker2 -- df -h /
echo "-- kubelet --"
multipass exec k8s-worker2 -- sudo systemctl is-active kubelet
echo "-- containerd --"
multipass exec k8s-worker2 -- sudo systemctl is-active containerd
echo ""
echo "=== Redis Health Summary ==="
if [ -n "$REDIS_POD" ]; then
  kubectl exec -n demo "$REDIS_POD" -- redis-cli ping 2>/dev/null \
    || echo "Redis ping FAILED"
  kubectl exec -n demo "$REDIS_POD" -- redis-cli info server 2>/dev/null \
    | grep -E "redis_version|uptime_in_seconds|tcp_port" \
    || echo "Could not get Redis server info"
else
  echo "No redis pod found"
fi
echo ""
echo "=== Backend Health Summary ==="
if [ -n "$BACKEND_POD" ]; then
  kubectl exec -n demo "$BACKEND_POD" -- \
    curl -s --max-time 3 http://localhost:5000/health 2>/dev/null \
    || echo "Backend health check FAILED"
else
  echo "No backend pod found"
fi
echo ""
echo "=== NodePort Reachability Summary ==="
for NODE_IP in 192.168.2.65 192.168.2.66; do
  RESULT=$(curl -o /dev/null -s -w "%{http_code}" \
    --max-time 5 http://${NODE_IP}:30500/health 2>/dev/null)
  echo "Worker ${NODE_IP}:30500/health -> HTTP ${RESULT}"
done
echo ""
echo "=== Clock Skew Summary ==="
MAC_TIME=$(date +%s)
W1_TIME=$(multipass exec k8s-worker1 -- date +%s)
W2_TIME=$(multipass exec k8s-worker2 -- date +%s)
echo "Worker1 skew vs Mac: $((W1_TIME - MAC_TIME)) seconds"
echo "Worker2 skew vs Mac: $((W2_TIME - MAC_TIME)) seconds"
echo ""
echo "=== Network Connectivity Summary ==="
for NODE_IP in 192.168.2.65 192.168.2.66; do
  ping -c 1 -W 1 "$NODE_IP" > /dev/null 2>&1 \
    && echo "REACHABLE:   $NODE_IP" \
    || echo "UNREACHABLE: $NODE_IP"
done
echo ""
echo "=== Deployment Readiness Summary ==="
kubectl get deployments -n demo \
  -o jsonpath='{range .items[*]}{.metadata.name}{" Desired: "}{.spec.replicas}{" Ready: "}{.status.readyReplicas}{"\n"}{end}'
echo ""
echo "=== HPA Summary ==="
kubectl get hpa -n demo 2>/dev/null || echo "No HPAs configured"
echo ""
echo "=== ResourceQuota Summary ==="
kubectl describe resourcequota -n demo 2>/dev/null || echo "No ResourceQuotas configured"
echo ""
echo "=== LimitRange Summary ==="
kubectl describe limitrange -n demo 2>/dev/null || echo "No LimitRanges configured"
echo ""
echo "========================================"
echo "=== END OF DIAGNOSTIC REPORT ==="
echo "Completed at: $(date)"
echo "========================================"

exit 0
