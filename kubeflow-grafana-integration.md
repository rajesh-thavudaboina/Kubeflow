## Install with a Single Command

## Add this userdata while launching instance.
```bash
#!/bin/bash
set -e

# --------------------------------------
# Log user-data execution
# --------------------------------------
exec > /var/log/user-data.log 2>&1

echo "Starting EC2 bootstrap..."

# --------------------------------------
# System update & Docker
# --------------------------------------
apt-get update -y
apt-get install -y docker.io curl

usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# --------------------------------------
# Install kind
# --------------------------------------
curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
chmod +x /usr/local/bin/kind

# --------------------------------------
# Install kubectl
# --------------------------------------
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# --------------------------------------
# Install Helm
# --------------------------------------
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

# --------------------------------------
# Install Kustomize
# --------------------------------------
curl -s https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash
mv kustomize /usr/local/bin/

# --------------------------------------
# Increase inotify limits (Kubeflow requirement)
# --------------------------------------
sysctl -w fs.inotify.max_user_instances=2280
sysctl -w fs.inotify.max_user_watches=1255360

cat <<EOF >> /etc/sysctl.conf
fs.inotify.max_user_instances=2280
fs.inotify.max_user_watches=1255360
EOF

# --------------------------------------
# Run cluster creation as ubuntu user
# --------------------------------------
su - ubuntu <<'EOF'

cat <<YAML > ~/kind-kubeflow.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.32.0@sha256:c48c62eac5da28cdadcf560d1d8616cfa6783b58f0d94cf63ad1bf49600cb027
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        "service-account-issuer": "https://kubernetes.default.svc"
        "service-account-signing-key-file": "/etc/kubernetes/pki/sa.key"
YAML

kind create cluster --config ~/kind-kubeflow.yaml

EOF
```

## Save Kubeconfig
```bash
kind get kubeconfig --name kubeflow > /tmp/kubeflow-config
export KUBECONFIG=/tmp/kubeflow-config
```

You can install all Kubeflow official components (residing under apps) and all common services (residing under common) using the following command:

```bash
while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do echo "Retrying to apply resources"; sleep 20; done
```

## Connect to Your Kubeflow Cluster
After installation, it will take some time for all Pods to become ready. Ensure all Pods are ready before trying to connect; otherwise, you might encounter unexpected errors. To check that all Kubeflow-related Pods are ready, use the following commands:

```bash
kubectl get pods -n cert-manager
kubectl get pods -n istio-system
kubectl get pods -n auth
kubectl get pods -n oauth2-proxy
kubectl get pods -n knative-serving
kubectl get pods -n kubeflow
kubectl get pods -n kubeflow-user-example-com
```

### Port-Forward
The default way of accessing Kubeflow is via port-forwarding. This enables you to get started quickly without imposing any requirements on your environment. Run the following to port-forward Istio's Ingress-Gateway to local port 8080:

```bash
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 --address 0.0.0.0 &
```

After running the command, you can access the Kubeflow Central Dashboard by doing the following:

1. Open your browser and visit http://localhost:8080 or http://<PublicIP>:8080 You should see the Dex login screen.
2. Log in with the default user's credentials. The default email address is user@example.com, and the default password is 12341234.