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
YAML

kind create cluster --config ~/kind-kubeflow.yaml

EOF

echo "EC2 bootstrap completed successfully"
