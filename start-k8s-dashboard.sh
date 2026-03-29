
###
(
echo "🚀 Deleting all these components first ..."
set -x
kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
kubectl -n kubernetes-dashboard delete Secret admin-user-token
kubectl -n kubernetes-dashboard delete token admin-user
kubectl delete ClusterRoleBinding admin-user
kubectl -n kubernetes-dashboard delete ServiceAccount admin-user
kubectl delete namespace kubernetes-dashboard
set +x
echo ""
) \
2> /dev/null

#echo "Press Enter to continue..." ; read

### 
echo "🚀 Creating kubernetes-dashboard namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: kubernetes-dashboard
EOF
echo ""

set -x
kubectl config get-contexts
kubectl config current-context
kubectl config set-context --current --namespace=kubernetes-dashboard
kubectl config current-context
set +x

###
echo "🚀 Installing the Kubernetes Dashboard...yaml file"
set -x
# Apply the official dashboard manifest (latest stable)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
set +x
echo ""

###
echo "🚀 Check if it's running..."
set -x
kubectl -n kubernetes-dashboard get pods 
kubectl -n kubernetes-dashboard get svc
set +x
echo ""

#echo "Press Enter to continue..." ; read

###
echo "🚀 Create ServiceAccount..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF
echo

echo "🚀 Create ClusterRoleBinding..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
echo 

echo "🚀 Create Secret..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF
echo

echo "🚀 Check all resources..."
set -x
kubectl get serviceaccount admin-user -n kubernetes-dashboard
kubectl get clusterrolebinding admin-user
kubectl get secret admin-user-token -n kubernetes-dashboard
set +x

#echo "Press Enter to continue..." ; read

set -x
kubectl get secret admin-user-token \
  -n kubernetes-dashboard \
  -o jsonpath="{.data.token}" | base64 --decode
set +x

# Save it to a file so you don't lose it
kubectl get secret admin-user-token \
  -n kubernetes-dashboard \
  -o jsonpath="{.data.token}" | base64 --decode > ./dashboard-token.txt
echo "Your token is saved in dashboard-token.txt"

set -x
kubectl patch deployment kubernetes-dashboard \
  -n kubernetes-dashboard \
  --type="json" \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-skip-login"}]'
set +x

set -x
kubectl patch deployment kubernetes-dashboard \
  -n kubernetes-dashboard \
  --type="json" \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--token-ttl=288000"}]'
set +x

# Get the token and decode it at jwt.io or use this command
kubectl get secret admin-user-token \
  -n kubernetes-dashboard \
  -o jsonpath="{.data.token}" | base64 --decode | cut -d. -f2 | base64 --decode 2>/dev/null

echo "# Check the deployment args..."
set -x
kubectl get deployment kubernetes-dashboard \
  -n kubernetes-dashboard \
  -o jsonpath='{.spec.template.spec.containers[0].args}'
set +x
echo "# Check the pod is running..."
set -x
kubectl get pods -n kubernetes-dashboard
set +x
echo "# Check pod logs..."
set -x
kubectl logs -n kubernetes-dashboard \
  deployment/kubernetes-dashboard
set +x

#echo "Press Enter to continue..." ; read

###
echo "🚀 Start the proxy..."
set -x
echo "kill -9 $(lsof -t -i :8001)"
echo "kubectl proxy &"
set +x

echo "Please wait a few secs..."
echo "Dashboard will open at: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo ""

#echo "Press Enter to continue..." ; read

###
echo "🚀 Creating kubernetes-dashboard nodeport..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-nodeport
  namespace: kubernetes-dashboard
spec:
  type: NodePort
  selector:
    k8s-app: kubernetes-dashboard
  ports:
  - port: 443
    targetPort: 8443
    nodePort: 30443
    protocol: TCP
EOF
echo ""

#echo "Press Enter to continue..." ; read

echo "🚀 Get nodeport ip, and then, access via browser: e.g. https://<NODE_IP>:30443 ..."
set -x
kubectl get nodes -o wide
set +x
echo ""

#echo "Press Enter to continue..." ; read

echo "🚀 Starting port forwarding..."
set -x
echo "kill -9 $(lsof -t -i :8443)"
echo "kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443 1> /dev/null 2>&1 &"
set +x
echo ""

###
# Check all resources in the namespace
set -x
kubectl get all -n kubernetes-dashboard
set +x
# Check service account
set -x
kubectl get serviceaccount admin-user -n kubernetes-dashboard
set +x
# Check cluster role binding
set -x
kubectl get clusterrolebinding admin-user
set +x
# Check events if something is wrong
set -x
kubectl get events -n kubernetes-dashboard --sort-by='.lastTimestamp'
set +x
echo ""
