#!/bin/bash

sudo apt-get update
sudo apt install docker.io -y
sudo usermod -aG docker ubuntu

[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh

curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/


# Increase inotify limits (critical for Kubeflow)
sudo sysctl fs.inotify.max_user_instances=2280
sudo sysctl fs.inotify.max_user_watches=1255360

# Make persistent
echo 'fs.inotify.max_user_instances=2280' | sudo tee -a /etc/sysctl.conf
echo 'fs.inotify.max_user_watches=1255360' | sudo tee -a /etc/sysctl.conf


cat <<EOF > kind-kubeflow.yaml
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
EOF

kind create cluster --config kind-kubeflow.yaml