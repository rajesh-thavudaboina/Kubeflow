

End-to-end setup of **Ray Dashboard** integrated with **Prometheus + Grafana** on a
KIND Kubernetes cluster running on an **AWS EC2** instance.

You will get:

- Ray Dashboard on `http://<EC2_PUBLIC_IP>:30000`
- Grafana on `http://<EC2_PUBLIC_IP>:30001`
- Prometheus scraping Ray metrics
- Grafana dashboards embedded inside Ray Dashboard → **Metrics** tab
- Ray’s official Grafana dashboards imported and working

---

## 0. Prerequisites

On your **EC2 instance**:

- Ubuntu (or similar Linux)
- Docker installed
- `kubectl`, `helm`, `kind`

Install quickly:

```bash
# Docker
sudo apt-get update
sudo apt install docker.io -y
sudo usermod -aG docker $USER && newgrp docker
docker --version

docker ps


# re-login so docker group is active, then:

# kind
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
kind version

# kubectl
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl
kubectl version --client


# helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh



Note: Log out and back in after adding your user to the docker group.

Set a helper env var with your EC2 public IP:


export EC2_PUBLIC_IP="YOUR_EC2_PUBLIC_IP_HERE"
1. Create KIND Cluster
Create KIND config:


cat > kind-ray.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30000
        hostPort: 30000
      - containerPort: 30001
        hostPort: 30001
      - containerPort: 30002
        hostPort: 30002
      - containerPort: 30003
        hostPort: 30003
  - role: worker
  - role: worker
EOF

Create cluster:

kind create cluster --name ray-cluster --config kind-ray.yaml
kubectl get nodes


2. Install KubeRay Operator

kubectl create namespace ray-system

helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

helm install kuberay-operator kuberay/kuberay-operator -n ray-system

kubectl get pods -n ray-system

You should see the kuberay-operator-... pod in Running state.


3. Deploy RayCluster with Dashboard + Metrics
Create Ray namespace:

kubectl create namespace ray
Create raycluster-dashboard.yaml:

bash
Copy code
cat > raycluster-dashboard.yaml <<EOF
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: raycluster-dashboard
  namespace: ray
spec:
  rayVersion: "2.9.3"
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
      metrics-export-port: "8080"
    serviceType: ClusterIP
    template:
      spec:
        containers:
          - name: ray-head
            image: rayproject/ray:2.9.3-py39
            env:
            - name: RAY_PROMETHEUS_HOST
              value: "http://kps-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
            - name: RAY_GRAFANA_HOST
              value: "http://kps-grafana.monitoring.svc.cluster.local"
            - name: RAY_GRAFANA_IFRAME_HOST
              value: "http://$EC2_PUBLIC_IP:30001"
            ports:
              - containerPort: 8265
                name: dashboard
              - containerPort: 8080
                name: metrics

  workerGroupSpecs:
    - groupName: small-group
      replicas: 1
      template:
        spec:
          containers:
            - name: ray-worker
              image: rayproject/ray:2.9.3-py39
EOF

kubectl apply -f raycluster-dashboard.yaml
kubectl get pods -n ray

You should see something like:

raycluster-dashboard-head-xxxxx                 1/1   Running
raycluster-dashboard-small-group-worker-yyyyy   1/1   Running

4. Expose Ray Dashboard via NodePort

cat > ray-dashboard-svc.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ray-dashboard-nodeport
  namespace: ray
spec:
  type: NodePort
  selector:
    ray.io/node-type: head
  ports:
    - name: dashboard
      port: 8265
      targetPort: 8265
      nodePort: 30000
EOF

kubectl apply -f ray-dashboard-svc.yaml
kubectl get svc -n ray
Access Ray Dashboard in browser:


http://$EC2_PUBLIC_IP:30000
5. Install Prometheus + Grafana (kube-prometheus-stack)
bash
Copy code
kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kps prometheus-community/kube-prometheus-stack -n monitoring

kubectl get pods -n monitoring
Wait until all pods in monitoring are Running.

6. Expose Grafana via NodePort

cat > grafana-nodeport.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: grafana-nodeport
  namespace: monitoring
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/instance: kps
  ports:
    - name: http
      port: 80
      targetPort: 3000
      nodePort: 30001
EOF

kubectl apply -f grafana-nodeport.yaml
kubectl get svc -n monitoring | grep grafana
Grafana URL:


http://$EC2_PUBLIC_IP:30001
Login:

User: admin

Password: from secret:


kubectl get secret kps-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d; echo
7. Enable Grafana Embedding (for Ray iframes)
Allow Grafana to be embedded and enable anonymous read-only access:


kubectl -n monitoring set env deployment/kps-grafana \
  GF_SECURITY_ALLOW_EMBEDDING=true \
  GF_AUTH_ANONYMOUS_ENABLED=true \
  GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer

kubectl rollout status deployment/kps-grafana -n monitoring
8. Expose Ray Metrics to Prometheus
8.1 Service on Ray Head (ray-head-metrics)
bash
Copy code
cat > ray-head-metrics-svc.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ray-head-metrics
  namespace: ray
  labels:
    ray.io/node-type: head
spec:
  selector:
    ray.io/node-type: head
  ports:
    - name: metrics
      port: 8080
      targetPort: 8080
EOF

kubectl apply -f ray-head-metrics-svc.yaml
kubectl get svc -n ray
8.2 PodMonitor (Prometheus CRD)
bash
Copy code
cat > ray-podmonitor.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: ray-head-monitor
  namespace: monitoring
  labels:
    release: kps
spec:
  namespaceSelector:
    matchNames:
      - ray
  selector:
    matchLabels:
      ray.io/node-type: head
  podMetricsEndpoints:
    - port: metrics
      path: /metrics
      interval: 15s
EOF

kubectl apply -f ray-podmonitor.yaml
kubectl get podmonitors -n monitoring
9. Verify Prometheus Has Ray Metrics
We’ll port-forward Prometheus (internal only, no NodePort needed):


kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0
Open in browser:


http://$EC2_PUBLIC_IP:39090
Go to Status → Targets, and verify a Ray target shows UP.

In Graph tab, try:

promql

ray_node_mem_total
ray_node_cpu_utilization
You should see metrics with labels like:


namespace="ray", pod="raycluster-dashboard-head-xxxxx", ...
10. Build Simple Grafana Panels (optional sanity check)
In Grafana (http://$EC2_PUBLIC_IP:30001):

Dashboards → New → New dashboard → Add new panel

Query examples:

promql

ray_node_cpu_utilization{pod=~"raycluster.*head.*"}
ray_node_mem_total{pod=~"raycluster.*head.*"}
Choose Time series visualization.

Save as e.g. Ray Test Dashboard.

If these work, your Prometheus ↔ Grafana ↔ Ray metrics are wired.

11. Import Ray’s Official Grafana Dashboards
Ray creates dashboard JSONs inside the head pod; we copy and import them.

11.1 Copy dashboards from Ray head to EC2

HEAD_POD=$(kubectl get pod -n ray -l ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')

# create tar of dashboards inside the pod
kubectl exec -n ray "$HEAD_POD" -- bash -c '
  cd /tmp/ray/session_latest/metrics && \
  tar czf /tmp/ray-dashboards.tgz grafana
'

# copy tar to EC2
mkdir -p ~/ray-grafana-dashboards
kubectl cp -n ray "$HEAD_POD":/tmp/ray-dashboards.tgz ~/ray-grafana-dashboards/ray-dashboards.tgz

# extract
cd ~/ray-grafana-dashboards
tar xzf ray-dashboards.tgz
ls grafana/dashboards
You should see files like:


default_grafana_dashboard.json
data_grafana_dashboard.json
serve_grafana_dashboard.json
serve_deployment_grafana_dashboard.json
11.2 Import JSONs into Grafana
In Grafana:

Dashboards → New → Import

Click Upload JSON file

Upload default_grafana_dashboard.json

Select the Prometheus datasource

Click Import

Repeat for:

data_grafana_dashboard.json

serve_grafana_dashboard.json

serve_deployment_grafana_dashboard.json

🔴 Important: Do not change the dashboard UID on import — Ray expects UIDs like rayDefaultDashboard.

12. Verify Ray Dashboard Integration
Back in Ray Dashboard:


http://$EC2_PUBLIC_IP:30000
Go to the Overview tab – you should see live CPU, memory, disk charts.

Go to the Metrics tab – tiles should now display Grafana panels instead of errors.

The dropdown in the Metrics tab (e.g., “Core Dashboard”, “Ray Data Dashboard”) should switch between dashboards.

If you right-click a tile → Open in new tab, you should see the corresponding Grafana dashboard (Core, Data, Serve).

13. Download Dashboard JSONs to Your Laptop
From your laptop terminal (not EC2):


scp -i /path/to/your-key.pem \
  ubuntu@$EC2_PUBLIC_IP:~/ray-grafana-dashboards/grafana/dashboards/* \
  ./ray-dashboards/
This copies all Ray dashboard JSONs into ./ray-dashboards on your laptop.

14. Troubleshooting Notes (Common Issues)
Ray pods stuck in ContainerCreating

Check kubectl describe pod -n ray <pod>

Usually image pull or volume issues.

Prometheus target for Ray DOWN

Confirm ray-head-metrics service exists.

Ensure PodMonitor label ray.io/node-type: head matches head pod labels.

Check Prometheus UI → Status → Targets.

Grafana panels empty

Test raw PromQL in Prometheus first.

Use correct labels, e.g.:

promql

ray_node_cpu_utilization{pod=~"raycluster.*head.*"}
Ray Metrics tab shows “set up Prometheus and Grafana”

Check Ray head env vars:

kubectl exec -n ray $(kubectl get pod -n ray -l ray.io/node-type=head -o name) -- env | grep RAY_
Ensure RAY_PROMETHEUS_HOST, RAY_GRAFANA_HOST, RAY_GRAFANA_IFRAME_HOST are set correctly.

Tiles show “dashboard ... not found (rayDefaultDashboard)”

Ray dashboards not imported to Grafana or UID changed.

Re-import JSONs and keep UIDs.

15. Summary
By following this README you will have:

A KIND cluster on EC2

KubeRay operator managing RayCluster

Ray Dashboard exposed via NodePort

Prometheus scraping Ray metrics

Grafana visualizing Ray metrics

Official Ray dashboards imported

Grafana panels embedded directly inside Ray Dashboard Metrics tab

Dashboard JSONs downloaded for reuse and backup