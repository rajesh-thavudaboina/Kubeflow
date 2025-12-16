# Kubeflow v1.10.0 Complete Installation Guide

## Prerequisites

- **RAM**: 16GB minimum (32GB recommended)
- **CPU**: 6 cores minimum (8+ recommended)
- **Disk**: 100GB free space
- **Docker**: Version 20.10+
- **OS**: Linux (Ubuntu 20.04+) or macOS

## Step 1: Install Required Tools
Before starting, ensure you have the following installed on your system:

1. **Docker** → Required for Kind to run containers as cluster nodes.

   ```bash
   sudo apt-get update
   sudo apt install docker.io -y
   sudo usermod -aG docker $USER && newgrp docker
   docker --version

   docker ps
   ```

2. **Kind (Kubernetes in Docker)** → To create the cluster.

  ```bash
  [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
  ```

   ```bash
   kind version
   ```

   [Install Guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)

3. **kubectl** → To interact with the cluster.
  ```bash
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  chmod +x kubectl
  mkdir -p ~/.local/bin
  mv ./kubectl ~/.local/bin/kubectl
  ```

   ```bash
   kubectl version --client
   ```

   [Install Guide](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

4. **Helm (for Helm-based installation)**
  ```bash
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
  chmod 700 get_helm.sh
  ./get_helm.sh
  ```

   ```bash
   helm version
   ```

   [Install Guide](https://helm.sh/docs/intro/install/)

5. **Install Kustomize**
```bash
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
  sudo mv kustomize /usr/local/bin/
  kustomize version
```

## Step 2: Configure System

```bash
# Increase inotify limits (critical for Kubeflow)
sudo sysctl fs.inotify.max_user_instances=2280
sudo sysctl fs.inotify.max_user_watches=1255360

# Make persistent
echo 'fs.inotify.max_user_instances=2280' | sudo tee -a /etc/sysctl.conf
echo 'fs.inotify.max_user_watches=1255360' | sudo tee -a /etc/sysctl.conf
```

## Step 3: Create Kind Cluster

Create `kind-kubeflow.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kubeflow
nodes:
- role: control-plane
  image: kindest/node:v1.33.1
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
  image: kindest/node:v1.33.1
- role: worker
  image: kindest/node:v1.33.1
```

```bash
# Create cluster
kind create cluster --config kind-kubeflow.yaml --wait 5m

# Verify
kubectl cluster-info
kubectl get nodes

# Apply inotify limits to Kind nodes
docker exec kubeflow-control-plane sysctl -w fs.inotify.max_user_instances=2280
docker exec kubeflow-control-plane sysctl -w fs.inotify.max_user_watches=1255360
docker exec kubeflow-worker sysctl -w fs.inotify.max_user_instances=2280
docker exec kubeflow-worker sysctl -w fs.inotify.max_user_watches=1255360
docker exec kubeflow-worker2 sysctl -w fs.inotify.max_user_instances=2280
docker exec kubeflow-worker2 sysctl -w fs.inotify.max_user_watches=1255360
```

## Step 4: Clone Kubeflow Manifests

```bash
cd ~
git clone https://github.com/kubeflow/manifests.git
cd manifests

# Checkout v1.10.0
git checkout v1.10.0

# Verify
git branch
# Should show: * (HEAD detached at v1.10.0)
```

## Step 5: Install cert-manager

```bash
echo "Installing cert-manager..."
kustomize build common/cert-manager/base | kubectl apply -f -
kustomize build common/cert-manager/kubeflow-issuer/base | kubectl apply -f -

echo "Waiting for cert-manager..."
kubectl wait --for=condition=Ready pod -l 'app in (cert-manager,webhook)' --timeout=300s -n cert-manager

echo "Verifying cert-manager..."
kubectl get pods -n cert-manager
```

## Step 6: Install Istio

```bash
echo "Installing Istio CRDs..."
kustomize build common/istio-1-24/istio-crds/base | kubectl apply -f -

echo "Installing Istio namespace..."
kustomize build common/istio-1-24/istio-namespace/base | kubectl apply -f -

echo "Installing Istio with oauth2-proxy support..."
kustomize build common/istio-1-24/istio-install/overlays/oauth2-proxy | kubectl apply -f -

echo "Waiting for Istio..."
kubectl wait --for=condition=Ready pod -l app=istiod -n istio-system --timeout=600s
kubectl wait --for=condition=Ready pod -l app=istio-ingressgateway -n istio-system --timeout=600s

echo "Verifying Istio..."
kubectl get pods -n istio-system
```

## Step 7: Install Dex

```bash
echo "Installing Dex..."
kustomize build common/dex/overlays/oauth2-proxy | kubectl apply -f -

echo "Waiting for Dex..."
kubectl wait --for=condition=Ready pods --all --timeout=300s -n auth

echo "Verifying Dex..."
kubectl get pods -n auth
```

## Step 8: Install OAuth2-Proxy

```bash
echo "Installing oauth2-proxy..."
kustomize build common/oauth2-proxy/overlays/m2m-dex-only/ | kubectl apply -f -

echo "Waiting for oauth2-proxy..."
kubectl wait --for=condition=Ready pod -l 'app.kubernetes.io/name=oauth2-proxy' --timeout=300s -n oauth2-proxy

echo "Verifying oauth2-proxy..."
kubectl get pods -n oauth2-proxy
```

## Step 9: Install Knative

```bash
echo "Installing Knative Serving..."
kustomize build common/knative/knative-serving/overlays/gateways | kubectl apply -f -
kustomize build common/istio-1-24/cluster-local-gateway/base | kubectl apply -f -

echo "Waiting for Knative Serving..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=knative-serving -n knative-serving --timeout=600s

echo "Installing Knative Eventing (optional)..."
kustomize build common/knative/knative-eventing/base | kubectl apply -f -

echo "Waiting for Knative Eventing..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=knative-eventing -n knative-eventing --timeout=600s

echo "Verifying Knative..."
kubectl get pods -n knative-serving
kubectl get pods -n knative-eventing
```

## Step 10: Install Kubeflow Namespace and Base

```bash
echo "Creating Kubeflow namespace..."
kustomize build common/kubeflow-namespace/base | kubectl apply -f -

echo "Installing network policies..."
kustomize build common/networkpolicies/base | kubectl apply -f -

echo "Installing Kubeflow roles..."
kustomize build common/kubeflow-roles/base | kubectl apply -f -

echo "Installing Kubeflow Istio resources..."
kustomize build common/istio-1-24/kubeflow-istio-resources/base | kubectl apply -f -

echo "Verifying Kubeflow namespace..."
kubectl get namespace kubeflow
```

## Step 11: Install Kubeflow Pipelines

```bash
echo "Installing Kubeflow Pipelines..."
kustomize build apps/pipeline/upstream/env/cert-manager/platform-agnostic-multi-user | kubectl apply -f -

echo "Waiting for Kubeflow Pipelines (this takes 5-7 minutes)..."
sleep 30
kubectl wait --for=condition=Ready pod -l app=ml-pipeline -n kubeflow --timeout=600s 2>/dev/null || true

echo "Verifying Pipelines..."
kubectl get pods -n kubeflow | grep pipeline
```

## Step 12: Install KServe

```bash
echo "Installing KServe..."
kustomize build apps/kserve/kserve | kubectl apply --server-side --force-conflicts -f -

echo "Waiting for KServe..."
kubectl wait --for=condition=Ready pod -l control-plane=kserve-controller-manager -n kubeflow --timeout=600s 2>/dev/null || true

echo "Installing KServe Models Web App..."
kustomize build apps/kserve/models-web-app/overlays/kubeflow | kubectl apply -f -

echo "Verifying KServe..."
kubectl get pods -n kubeflow | grep kserve
```

## Step 13: Install Katib

```bash
echo "Installing Katib..."
kustomize build apps/katib/upstream/installs/katib-with-kubeflow | kubectl apply -f -

echo "Waiting for Katib..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=katib-controller -n kubeflow --timeout=600s 2>/dev/null || true

echo "Verifying Katib..."
kubectl get pods -n kubeflow | grep katib
```

## Step 14: Install Central Dashboard

```bash
echo "Installing Central Dashboard..."
kustomize build apps/centraldashboard/overlays/oauth2-proxy | kubectl apply -f -

echo "Waiting for Central Dashboard..."
kubectl wait --for=condition=Ready pod -l app=centraldashboard -n kubeflow --timeout=300s

echo "Verifying Central Dashboard..."
kubectl get pods -n kubeflow | grep centraldashboard
```

## Step 15: Install Admission Webhook

```bash
echo "Installing Admission Webhook..."
kustomize build apps/admission-webhook/upstream/overlays/cert-manager | kubectl apply -f -

echo "Waiting for Admission Webhook..."
kubectl wait --for=condition=Ready pod -l app=admission-webhook -n kubeflow --timeout=300s

echo "Verifying Admission Webhook..."
kubectl get pods -n kubeflow | grep admission-webhook
```

## Step 16: Install Notebook Controller

```bash
echo "Installing Notebook Controller..."
kustomize build apps/jupyter/notebook-controller/upstream/overlays/kubeflow | kubectl apply -f -

echo "Waiting for Notebook Controller..."
kubectl wait --for=condition=Ready pod -l app=notebook-controller -n kubeflow --timeout=300s

echo "Verifying Notebook Controller..."
kubectl get pods -n kubeflow | grep notebook-controller
```

## Step 17: Install Jupyter Web App

```bash
echo "Installing Jupyter Web App..."
kustomize build apps/jupyter/jupyter-web-app/upstream/overlays/istio | kubectl apply -f -

echo "Waiting for Jupyter Web App..."
kubectl wait --for=condition=Ready pod -l app=jupyter-web-app -n kubeflow --timeout=300s

echo "Verifying Jupyter Web App..."
kubectl get pods -n kubeflow | grep jupyter-web-app
```

## Step 18: Install PVC Viewer Controller

```bash
echo "Installing PVC Viewer Controller..."
kustomize build apps/pvcviewer-controller/upstream/base | kubectl apply -f -

echo "Waiting for PVC Viewer Controller..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=pvcviewer-controller -n kubeflow --timeout=300s 2>/dev/null || true

echo "Verifying PVC Viewer Controller..."
kubectl get pods -n kubeflow | grep pvcviewer
```

## Step 19: Install Profiles + KFAM

```bash
echo "Installing Profiles and KFAM..."
kustomize build apps/profiles/upstream/overlays/kubeflow | kubectl apply -f -

echo "Waiting for Profiles..."
kubectl wait --for=condition=Ready pod -l kustomize.component=profiles -n kubeflow --timeout=300s

echo "Verifying Profiles..."
kubectl get pods -n kubeflow | grep profiles
```

## Step 20: Install Volumes Web App

```bash
echo "Installing Volumes Web App..."
kustomize build apps/volumes-web-app/upstream/overlays/istio | kubectl apply -f -

echo "Waiting for Volumes Web App..."
kubectl wait --for=condition=Ready pod -l app=volumes-web-app -n kubeflow --timeout=300s

echo "Verifying Volumes Web App..."
kubectl get pods -n kubeflow | grep volumes-web-app
```

## Step 21: Install Tensorboard

```bash
echo "Installing Tensorboards Web App..."
kustomize build apps/tensorboard/tensorboards-web-app/upstream/overlays/istio | kubectl apply -f -

echo "Installing Tensorboard Controller..."
kustomize build apps/tensorboard/tensorboard-controller/upstream/overlays/kubeflow | kubectl apply -f -

echo "Waiting for Tensorboard components..."
kubectl wait --for=condition=Ready pod -l app=tensorboards-web-app -n kubeflow --timeout=300s
kubectl wait --for=condition=Ready pod -l app=tensorboard-controller -n kubeflow --timeout=300s 2>/dev/null || true

echo "Verifying Tensorboard..."
kubectl get pods -n kubeflow | grep tensorboard
```

## Step 22: Install Training Operator

```bash
echo "Installing Training Operator..."
kustomize build apps/training-operator/upstream/overlays/kubeflow | kubectl apply --server-side --force-conflicts -f -

echo "Waiting for Training Operator..."
kubectl wait --for=condition=Ready pod -l control-plane=kubeflow-training-operator -n kubeflow --timeout=300s

echo "Verifying Training Operator..."
kubectl get pods -n kubeflow | grep training-operator
```

## Step 23: Create User Namespace

```bash
echo "Creating user namespace..."
kubectl apply -k common/user-namespace/base/

echo "Verifying user namespace..."
kubectl get profiles
kubectl get namespace kubeflow-user-example-com
```

## Step 24: Complete Verification

```bash
# Save this as check-all.sh
cat > check-all.sh <<'EOF'
#!/bin/bash

echo "=========================================="
echo "Kubeflow v1.10.0 Installation Verification"
echo "=========================================="
echo ""

NAMESPACES=("cert-manager" "istio-system" "auth" "oauth2-proxy" "knative-serving" "knative-eventing" "kubeflow" "kubeflow-user-example-com")

for ns in "${NAMESPACES[@]}"; do
    echo "--- Namespace: $ns ---"
    kubectl get pods -n $ns 2>/dev/null || echo "Namespace not found"
    echo ""
done

echo "=========================================="
echo "Checking for any non-running pods..."
echo "=========================================="
kubectl get pods -A | grep -v "Running\|Completed" | grep -v "NAMESPACE"

echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
kubectl get profiles
echo ""
echo "Installation complete!"
echo "Access Kubeflow with: kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 --address=0.0.0.0 &"
echo "Then visit: http://localhost:8080"
echo "Default credentials: user@example.com / 12341234"
EOF

chmod +x check-all.sh
./check-all.sh
```

## Step 25: Access Kubeflow

```bash
# Port forward in one terminal
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 --address=0.0.0.0 &

# Access at: http://localhost:8080
# Email: user@example.com
# Password: 12341234
```

## Complete Installation Script

Save this as `install-kubeflow-v1.10.sh`:

```bash
#!/bin/bash
set -e

echo "Starting Kubeflow v1.10.0 installation..."
cd ~/manifests

components=(
    "common/cert-manager/base"
    "common/cert-manager/kubeflow-issuer/base"
    "common/istio-1-24/istio-crds/base"
    "common/istio-1-24/istio-namespace/base"
    "common/istio-1-24/istio-install/overlays/oauth2-proxy"
    "common/dex/overlays/oauth2-proxy"
    "common/oauth2-proxy/overlays/m2m-dex-only"
    "common/knative/knative-serving/overlays/gateways"
    "common/istio-1-24/cluster-local-gateway/base"
    "common/knative/knative-eventing/base"
    "common/kubeflow-namespace/base"
    "common/networkpolicies/base"
    "common/kubeflow-roles/base"
    "common/istio-1-24/kubeflow-istio-resources/base"
    "apps/pipeline/upstream/env/cert-manager/platform-agnostic-multi-user"
    "apps/kserve/models-web-app/overlays/kubeflow"
    "apps/katib/upstream/installs/katib-with-kubeflow"
    "apps/centraldashboard/overlays/oauth2-proxy"
    "apps/admission-webhook/upstream/overlays/cert-manager"
    "apps/jupyter/notebook-controller/upstream/overlays/kubeflow"
    "apps/jupyter/jupyter-web-app/upstream/overlays/istio"
    "apps/pvcviewer-controller/upstream/base"
    "apps/profiles/upstream/overlays/kubeflow"
    "apps/volumes-web-app/upstream/overlays/istio"
    "apps/tensorboard/tensorboards-web-app/upstream/overlays/istio"
    "apps/tensorboard/tensorboard-controller/upstream/overlays/kubeflow"
    "apps/training-operator/upstream/overlays/kubeflow"
    "common/user-namespace/base"
)

for component in "${components[@]}"; do
    echo ""
    echo "=========================================="
    echo "Installing: $component"
    echo "=========================================="
    
    if [[ $component == *"kserve/kserve"* ]] || [[ $component == *"training-operator"* ]]; then
        kustomize build "$component" | kubectl apply --server-side --force-conflicts -f -
    else
        kustomize build "$component" | kubectl apply -k -
    fi
    
    sleep 10
done

# Special handling for KServe
echo "Installing KServe..."
kustomize build apps/kserve/kserve | kubectl apply --server-side --force-conflicts -f -

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo "Waiting for all pods to be ready (this may take 10-15 minutes)..."
echo "Run './check-all.sh' to verify installation"
```

## Troubleshooting

### Issue 1: CRD Not Established

```bash
# If you see "no matches for kind" errors
# Wait 30 seconds and retry:
sleep 30
kustomize build <path> | kubectl apply -f -
```

### Issue 2: Pods Not Starting

```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl describe pod <pod-name> -n <namespace>

# Check resource usage
kubectl top nodes
kubectl top pods -n kubeflow
```

### Issue 3: Clean Restart

```bash
# Delete cluster
kind delete cluster --name kubeflow

# Restart from Step 3
```

## Time Estimates

- **Cluster Creation**: 3 minutes
- **cert-manager**: 2 minutes
- **Istio**: 3 minutes
- **Dex + oauth2-proxy**: 2 minutes
- **Knative**: 3 minutes
- **Kubeflow Pipelines**: 5-7 minutes
- **Other components**: 10-15 minutes
- **Total**: 30-40 minutes

## Next Steps

1. **Create a notebook**:
```bash
kubectl apply -f test-notebook.yaml -n kubeflow-user-example-com
```

2. **Run a pipeline**: Access Pipeline UI at http://localhost:8080/pipeline

3. **Train a model**: Use Training Operator

4. **Serve a model**: Use KServe

## Additional Resources

- Official docs: https://www.kubeflow.org/docs/
- GitHub: https://github.com/kubeflow/manifests
- Release notes: https://github.com/kubeflow/manifests/releases/tag/v1.10.0


Excellent! Your Kubeflow v1.10.0 installation is complete and all pods are running! 🎉

However, you're encountering a **CSRF token error** when trying to create a notebook. This is a common issue related to cookie/session handling. Let me help you fix this:

## Quick Fix for CSRF Error

🥈 OPTION 2 (Quick Dev Fix): Disable CSRF Check (NOT for prod)

If this is only a demo / learning setup, you can disable the check.

Patch jupyter-web-app deployment
kubectl edit deployment jupyter-web-app-deployment -n kubeflow


Add env var:

env:
- name: APP_SECURE_COOKIES
  value: "false"


Restart:

kubectl rollout restart deployment jupyter-web-app-deployment -n kubeflow


⚠️ Not recommended for production

🥉 OPTION 3 (EASIEST): Continue using YAML (Already Working)

Since this works perfectly:

kubectl apply -f my-notebook.yaml


You can:

Ignore UI creation

Use UI only to Connect to notebooks

This is very common in real teams.

🔍 Why CSRF Happens Specifically Here

Kubeflow UI stack:

Browser
  ↓ cookies
Istio Gateway
  ↓ headers
Kubeflow Central Dashboard
  ↓ auth
Jupyter Web App


When you access via :8080:

Cookies not set

Origin mismatch

CSRF token missing

Backend blocks request

### Solution 1: Clear Browser Cache and Cookies (Fastest)

```bash
# 1. Stop the port-forward
# Press Ctrl+C on the terminal running port-forward

# 2. Clear your browser cache and cookies for localhost:8080

# 3. Restart port-forward
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80

# 4. Open a fresh incognito/private window
# Visit: http://localhost:8080
# Login again with: user@example.com / 12341234
```

### Solution 2: Use Different Port

The issue might be with port 8080. Try a different port:

```bash
# Stop current port-forward (Ctrl+C)

# Use port 8888 instead
kubectl port-forward svc/istio-ingressgateway -n istio-system 8888:80

# Access at: http://localhost:8888
```

### Solution 3: Check and Fix OAuth2-Proxy Configuration

The CSRF error often relates to OAuth2-Proxy cookie settings. Let's verify:

```bash
# Check oauth2-proxy configuration
kubectl get configmap oauth2-proxy -n oauth2-proxy -o yaml

# Check if oauth2-proxy pods are healthy
kubectl logs -n oauth2-proxy -l app.kubernetes.io/name=oauth2-proxy --tail=50
```

### Solution 4: Restart OAuth2-Proxy Pods

```bash
# Restart oauth2-proxy pods
kubectl rollout restart deployment oauth2-proxy -n oauth2-proxy

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=oauth2-proxy -n oauth2-proxy --timeout=120s

# Restart port-forward
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
```

### Solution 5: Create Notebook via kubectl (Workaround)

While we fix the UI issue, you can create notebooks directly with kubectl:

```bash
# Create a file: my-notebook.yaml
cat <<EOF > my-notebook.yaml
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: my-jupyter-notebook
  namespace: kubeflow-user-example-com
spec:
  template:
    spec:
      serviceAccountName: default-editor
      containers:
      - name: notebook
        image: jupyter/minimal-notebook:python-3.10
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
        volumeMounts:
        - name: workspace
          mountPath: /home/jovyan
      volumes:
      - name: workspace
        persistentVolumeClaim:
          claimName: my-jupyter-notebook-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-jupyter-notebook-pvc
  namespace: kubeflow-user-example-com
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Apply the notebook
kubectl apply -f my-notebook.yaml

# Check notebook status
kubectl get notebooks -n kubeflow-user-example-com
kubectl get pods -n kubeflow-user-example-com

# Wait for notebook to be ready
kubectl wait --for=condition=Ready pod -l notebook-name=my-jupyter-notebook -n kubeflow-user-example-com --timeout=300s

# Once ready, you'll see it in the UI
```

### Solution 6: Check Istio Virtual Service

The CSRF issue might be related to Istio routing:

```bash
# Check the jupyter virtual service
kubectl get virtualservice -n kubeflow

# Check jupyter-web-app logs
kubectl logs -n kubeflow -l app=jupyter-web-app --tail=100

# Restart jupyter-web-app
kubectl rollout restart deployment jupyter-web-app-deployment -n kubeflow
```

### Solution 7: Verify Cookie Domain Settings

Check if the cookie domain is set correctly:

```bash
# Edit oauth2-proxy config
kubectl edit configmap oauth2-proxy -n oauth2-proxy

# Look for these settings (they should be present):
# cookie-domain: ".localhost"
# cookie-secure: "false"
# cookie-samesite: "lax"

# If they're missing or incorrect, add/update them, then:
kubectl rollout restart deployment oauth2-proxy -n oauth2-proxy
```

### Complete Debug and Fix Script

Save this as `fix-csrf.sh`:

```bash
#!/bin/bash

echo "Fixing CSRF token issue..."

# 1. Restart oauth2-proxy
echo "Restarting oauth2-proxy..."
kubectl rollout restart deployment oauth2-proxy -n oauth2-proxy
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=oauth2-proxy -n oauth2-proxy --timeout=120s

# 2. Restart jupyter-web-app
echo "Restarting jupyter-web-app..."
kubectl rollout restart deployment jupyter-web-app-deployment -n kubeflow
kubectl wait --for=condition=Ready pod -l app=jupyter-web-app -n kubeflow --timeout=120s

# 3. Restart centraldashboard
echo "Restarting centraldashboard..."
kubectl rollout restart deployment centraldashboard -n kubeflow
kubectl wait --for=condition=Ready pod -l app=centraldashboard -n kubeflow --timeout=120s

echo ""
echo "Components restarted. Please:"
echo "1. Clear your browser cache and cookies"
echo "2. Close all browser windows"
echo "3. Restart port-forward: kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80"
echo "4. Open fresh browser window to http://localhost:8080"
echo "5. Login with: user@example.com / 12341234"
```

```bash
chmod +x fix-csrf.sh
./fix-csrf.sh
```

## Most Likely Solution

Based on the error, the **most common fix** is:

1. **Clear browser cache completely**
2. **Use incognito/private window**
3. **Restart port-forward**

Try this first before the other solutions!

Let me know which solution works for you, or if you need more help debugging the CSRF issue!