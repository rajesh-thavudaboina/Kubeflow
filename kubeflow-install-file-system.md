# Complete Production-Grade Kubeflow v1.10.2 Installation Guide

Let me walk you through a comprehensive, production-ready installation of Kubeflow v1.10.2 based on your manifests structure.

## 📋 Prerequisites

### 1. **Kubernetes Cluster Requirements**
- **Kubernetes version**: 1.25+ (recommended: 1.27 or 1.28)
- **Minimum resources**:
  - 3+ worker nodes
  - 4 CPU cores per node
  - 16GB RAM per node
  - 100GB storage per node
- **Storage**: Dynamic storage provisioner (StorageClass with dynamic PV provisioning)

### 2. **Tools Installation**
```bash
# Install kubectl (if not already installed)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install kustomize v5.0.0+
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

# Verify versions
kubectl version --client
kustomize version
```

---

## 🏗️ Architecture Overview

Your Kubeflow installation will include:

1. **Core Components**:
   - **Istio**: Service mesh for traffic management & security
   - **Cert-Manager**: Automatic TLS certificate management
   - **Dex**: Identity provider for authentication
   - **OAuth2-Proxy**: Authentication proxy

2. **Kubeflow Components**:
   - **Central Dashboard**: Main UI
   - **Jupyter Notebooks**: Interactive development
   - **Kubeflow Pipelines**: ML workflow orchestration
   - **Katib**: Hyperparameter tuning
   - **KServe**: Model serving
   - **Training Operator**: Distributed training (TensorFlow, PyTorch, etc.)
   - **Volumes Web App**: PVC management
   - **Tensorboard**: Visualization
   - **Profile Controller**: Multi-tenancy

---

## 📦 Step-by-Step Installation

### **Step 1: Prepare Your Cluster**

```bash
# Set your working directory
cd ~/manifests

# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes

# Create a namespace for Kubeflow
kubectl create namespace kubeflow
```

### **Step 2: Install Cert-Manager** (Certificate Management)

```bash
# Install cert-manager CRDs and controller
kustomize build common/cert-manager/base | kubectl apply -f -

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Install Kubeflow self-signed issuer
kustomize build common/cert-manager/kubeflow-issuer/base | kubectl apply -f -
```

**What this does**: Manages SSL/TLS certificates automatically for secure HTTPS connections.

---

### **Step 3: Install Istio** (Service Mesh)

```bash
# Install Istio CRDs
kustomize build common/istio/istio-crds/base | kubectl apply -f -

# Install Istio namespace
kustomize build common/istio/istio-namespace/base | kubectl apply -f -

# Install Istio control plane
kustomize build common/istio/istio-install/base | kubectl apply -f -

# Wait for Istio to be ready
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=600s
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=600s

# Install cluster-local gateway (for internal services)
kustomize build common/istio/cluster-local-gateway/base | kubectl apply -f -

# Install Kubeflow Istio resources
kustomize build common/istio/kubeflow-istio-resources/base | kubectl apply -f -
```

**What this does**: 
- Creates a service mesh for secure service-to-service communication
- Provides ingress gateway for external access
- Enables traffic management, observability, and security policies

---

### **Step 4: Install Dex** (Identity Provider)

```bash
# Install Dex
kustomize build common/dex/overlays/istio | kubectl apply -f -

# Wait for Dex to be ready
kubectl wait --for=condition=ready pod -l app=dex -n auth --timeout=300s
```

**Configuration Required**: Edit `common/dex/base/config-map.yaml` to customize:

```yaml
# Default configuration includes a static user
# Email: user@example.com
# Password: 12341234

# To add more users, edit common/dex/base/config-map.yaml:
staticPasswords:
- email: admin@example.com
  hash: $2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W  # "password"
  username: admin
  userID: "08a8684b-db88-4b73-90a9-3cd1661f5466"
```

**To generate password hash**:
```bash
# Install htpasswd
sudo apt-get install apache2-utils

# Generate bcrypt hash
htpasswd -bnBC 10 "" your-password | tr -d ':\n'
```

---

### **Step 5: Install OAuth2-Proxy** (Authentication Gateway)

```bash
# Install OAuth2-Proxy
kustomize build common/oauth2-proxy/overlays/m2m-dex-only | kubectl apply -f -

# Wait for OAuth2-Proxy to be ready
kubectl wait --for=condition=ready pod -l app=oauth2-proxy -n oauth2-proxy --timeout=300s
```

**What this does**: Acts as authentication proxy between users and Kubeflow services.

---

### **Step 6: Install Knative** (Serverless - Required for KServe)

```bash
# Install Knative Serving
kustomize build common/knative/knative-serving/overlays/gateways | kubectl apply -f -

# Wait for Knative to be ready
kubectl wait --for=condition=ready pod -l app=controller -n knative-serving --timeout=300s

# Install Knative Eventing (optional but recommended)
kustomize build common/knative/knative-eventing/base | kubectl apply -f -
```

---

### **Step 7: Install Kubeflow Namespace & Roles**

```bash
# Create Kubeflow namespace
kustomize build common/kubeflow-namespace/base | kubectl apply -f -

# Install Kubeflow roles
kustomize build common/kubeflow-roles/base | kubectl apply -f -
```

---

### **Step 8: Install Kubeflow Pipelines**

```bash
# Install Kubeflow Pipelines (multi-user with MySQL)
kustomize build applications/pipeline/upstream/env/platform-agnostic-multi-user | kubectl apply -f -

# Wait for all pipeline components to be ready (this takes 5-10 minutes)
kubectl wait --for=condition=ready pod -l app=ml-pipeline -n kubeflow --timeout=600s
kubectl wait --for=condition=ready pod -l app=ml-pipeline-ui -n kubeflow --timeout=600s
kubectl wait --for=condition=ready pod -l app=cache-server -n kubeflow --timeout=600s
```

**Configuration Options** in `applications/pipeline/upstream/env/platform-agnostic-multi-user/`:
- **Database**: Default uses MySQL. For PostgreSQL, use `platform-agnostic-postgresql`
- **Object Storage**: Configure in pipeline install config for S3/MinIO/GCS

---

### **Step 9: Install KServe** (Model Serving)

```bash
# Install KServe
kustomize build applications/kserve/kserve | kubectl apply -f -

# Install KServe Models Web App
kustomize build applications/kserve/models-web-app/overlays/kubeflow | kubectl apply -f -

# Wait for KServe to be ready
kubectl wait --for=condition=ready pod -l control-plane=kserve-controller-manager -n kubeflow --timeout=600s
```

**What this does**: Enables model serving with autoscaling, canary deployments, and A/B testing.

---

### **Step 10: Install Katib** (Hyperparameter Tuning)

```bash
# Install Katib with Kubeflow integration
kustomize build applications/katib/upstream/installs/katib-with-kubeflow | kubectl apply -f -

# Wait for Katib to be ready
kubectl wait --for=condition=ready pod -l katib.kubeflow.org/component=controller -n kubeflow --timeout=600s
kubectl wait --for=condition=ready pod -l katib.kubeflow.org/component=ui -n kubeflow --timeout=300s
```

**Configuration**: Edit `applications/katib/upstream/installs/katib-with-kubeflow/katib-config.yaml` for:
- Suggestion algorithms
- Metrics collector settings
- Early stopping configurations

---

### **Step 11: Install Central Dashboard**

```bash
# Install Central Dashboard with OAuth2-Proxy integration
kustomize build applications/centraldashboard/overlays/oauth2-proxy | kubectl apply -f -

# Wait for dashboard to be ready
kubectl wait --for=condition=ready pod -l app=centraldashboard -n kubeflow --timeout=300s
```

---

### **Step 12: Install Jupyter Notebooks**

```bash
# Install Jupyter Web App
kustomize build applications/jupyter/jupyter-web-app/upstream/overlays/istio | kubectl apply -f -

# Install Notebook Controller
kustomize build applications/jupyter/notebook-controller/upstream/overlays/kubeflow | kubectl apply -f -

# Wait for components to be ready
kubectl wait --for=condition=ready pod -l app=jupyter-web-app -n kubeflow --timeout=300s
kubectl wait --for=condition=ready pod -l app=notebook-controller -n kubeflow --timeout=300s
```

---

### **Step 13: Install Profiles Controller** (Multi-Tenancy)

```bash
# Install Profiles with Kubeflow integration
kustomize build applications/profiles/upstream/overlays/kubeflow | kubectl apply -f -

# Wait for profile controller to be ready
kubectl wait --for=condition=ready pod -l kustomize.component=profiles -n kubeflow --timeout=300s
```

**What this does**: Manages user namespaces and RBAC for multi-user isolation.

---

### **Step 14: Install Training Operator**

```bash
# Install Training Operator for distributed training
kustomize build applications/training-operator/upstream/overlays/kubeflow | kubectl apply -f -

# Wait for training operator to be ready
kubectl wait --for=condition=ready pod -l control-plane=kubeflow-training-operator -n kubeflow --timeout=300s
```

**Supports**: TensorFlow, PyTorch, MXNet, XGBoost, MPI jobs

---

### **Step 15: Install Tensorboard**

```bash
# Install Tensorboard Controller
kustomize build applications/tensorboard/tensorboard-controller/upstream/overlays/kubeflow | kubectl apply -f -

# Install Tensorboard Web App
kustomize build applications/tensorboard/tensorboards-web-app/upstream/overlays/istio | kubectl apply -f -

# Wait for components to be ready
kubectl wait --for=condition=ready pod -l app=tensorboard-controller -n kubeflow --timeout=300s
kubectl wait --for=condition=ready pod -l app=tensorboards-web-app -n kubeflow --timeout=300s
```

---

### **Step 16: Install Volumes Web App**

```bash
# Install Volumes Web App for PVC management
kustomize build applications/volumes-web-app/upstream/overlays/istio | kubectl apply -f -

# Wait for it to be ready
kubectl wait --for=condition=ready pod -l app=volumes-web-app -n kubeflow --timeout=300s
```

---

### **Step 17: Install Admission Webhook**

```bash
# Install PodDefaults admission webhook with cert-manager
kustomize build applications/admission-webhook/upstream/overlays/cert-manager | kubectl apply -f -

# Wait for webhook to be ready
kubectl wait --for=condition=ready pod -l app=poddefaults -n kubeflow --timeout=300s
```

---

### **Step 18: Create Default User Profile**

```bash
# Create a profile for the default user
cat <<EOF | kubectl apply -f -
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: kubeflow-user-example-com
spec:
  owner:
    kind: User
    name: user@example.com
  resourceQuotaSpec:
    hard:
      cpu: "20"
      memory: 50Gi
      requests.nvidia.com/gpu: "4"
      persistentvolumeclaims: "20"
EOF

# Verify profile creation
kubectl get profile
```

---

### **Step 19: Access Kubeflow Dashboard**

```bash
# Port-forward to access the dashboard
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80

# Open browser to: http://localhost:8080
# Login with:
#   Email: user@example.com
#   Password: 12341234
```

**For Production LoadBalancer**:
```bash
# Get the external IP
kubectl get svc istio-ingressgateway -n istio-system

# Configure DNS to point to this IP
# Example: kubeflow.yourdomain.com -> EXTERNAL-IP
```

---

## 🔧 Production Configurations

### **1. Configure External Domain**

Edit `common/istio/istio-install/base/gateway.yaml`:
```yaml
spec:
  servers:
  - hosts:
    - "kubeflow.yourdomain.com"
    port:
      name: http
      number: 80
      protocol: HTTP
```

### **2. Enable HTTPS with Let's Encrypt**

Edit `common/cert-manager/kubeflow-issuer/base/cluster-issuer.yaml`:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@yourdomain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
```

### **3. Configure Object Storage (S3/MinIO)**

Edit `applications/pipeline/upstream/base/installs/generic/pipeline-install-config.yaml`:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pipeline-install-config
data:
  bucketName: "mlpipeline"
  minioServiceHost: "minio-service.kubeflow"
  minioServicePort: "9000"
  # For AWS S3:
  # bucketName: "your-s3-bucket"
  # s3Endpoint: "s3.amazonaws.com"
```

### **4. Configure Resource Quotas**

Edit profile resource quotas in `common/user-namespace/base/profile-instance.yaml`:
```yaml
spec:
  resourceQuotaSpec:
    hard:
      cpu: "50"
      memory: "200Gi"
      requests.nvidia.com/gpu: "8"
      persistentvolumeclaims: "50"
```

### **5. Enable GPU Support**

Install NVIDIA device plugin:
```bash
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
```

### **6. Configure Network Policies** (Production Security)

```bash
# Enable network policies for isolation
kustomize build common/networkpolicies/base | kubectl apply -f -
```

---

## 🔐 Security Hardening

### **1. Enable Pod Security Standards (PSS)**

```bash
# Apply restricted PSS to user namespaces
kubectl label namespace kubeflow-user-example-com \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

### **2. Change Default Passwords**

**Update Dex passwords**:
```bash
# Edit common/dex/base/config-map.yaml
# Generate new password hash:
htpasswd -bnBC 10 "" NewSecurePassword123! | tr -d ':\n'
# Update the config map and reapply
```

**Update MySQL passwords**:
```bash
# Edit applications/pipeline/upstream/env/platform-agnostic-multi-user/params.env
# Update applications/pipeline/upstream/base/installs/generic/mysql-secret.yaml
```

### **3. Enable mTLS**

Edit `common/istio/istio-install/base/patches/istio-configmap-disable-tracing.yaml`:
```yaml
data:
  mesh: |-
    defaultConfig:
      proxyMetadata: {}
    enablePrometheusMerge: true
    # Enable strict mTLS
    defaultConfig:
      proxyMetadata:
        ISTIO_META_TLS_MODE: "ISTIO_MUTUAL"
```

---

## 📊 Monitoring & Logging

### **Install Prometheus (Optional)**
```bash
# For pipeline metrics
kustomize build applications/pipeline/upstream/third-party/prometheus | kubectl apply -f -
```

### **View Logs**
```bash
# View all Kubeflow pods
kubectl get pods -n kubeflow

# View specific component logs
kubectl logs -n kubeflow -l app=ml-pipeline --tail=100

# Stream logs
kubectl logs -n kubeflow -l app=ml-pipeline -f
```

---

## 🧪 Verification & Testing

```bash
# 1. Check all pods are running
kubectl get pods -n kubeflow
kubectl get pods -n istio-system
kubectl get pods -n auth
kubectl get pods -n cert-manager
kubectl get pods -n knative-serving

# 2. Verify services
kubectl get svc -n kubeflow
kubectl get svc -n istio-system

# 3. Check ingress gateway
kubectl get svc istio-ingressgateway -n istio-system

# 4. Test pipeline API
kubectl port-forward -n kubeflow svc/ml-pipeline 8888:8888
curl http://localhost:8888/apis/v1beta1/healthz

# 5. Verify profiles
kubectl get profiles
```

---

## 🐛 Troubleshooting

### Common Issues:

**1. Pods stuck in Pending**:
```bash
kubectl describe pod <pod-name> -n kubeflow
# Check: Insufficient resources, PVC mounting issues
```

**2. Istio sidecar injection not working**:
```bash
kubectl label namespace kubeflow istio-injection=enabled
kubectl rollout restart deployment -n kubeflow
```

**3. Authentication issues**:
```bash
# Check Dex logs
kubectl logs -n auth -l app=dex

# Check OAuth2-Proxy logs
kubectl logs -n oauth2-proxy -l app=oauth2-proxy
```

**4. Pipeline failures**:
```bash
# Check MySQL connectivity
kubectl exec -it -n kubeflow deploy/mysql -- mysql -u root -ptest

# Check MinIO/object storage
kubectl port-forward -n kubeflow svc/minio-service 9000:9000
```

---

## 📝 Important Configuration Files

### Files You Should Customize:

1. **`common/dex/base/config-map.yaml`** - User authentication
2. **`common/dex/base/secret_params.env`** - OAuth secrets
3. **`applications/pipeline/upstream/base/installs/generic/pipeline-install-config.yaml`** - Object storage
4. **`common/istio/istio-install/base/gateway.yaml`** - External access domain
5. **`common/user-namespace/base/params.env`** - Default user namespace
6. **Resource quotas in profile definitions**

### Optional Configurations:

- `applications/katib/upstream/installs/katib-with-kubeflow/katib-config.yaml` - HP tuning
- `applications/kserve/kserve/params.env` - Model serving settings
- `common/networkpolicies/base/*` - Network isolation
- Storage class configurations for PVCs

---

## 🚀 Next Steps

1. **Create additional user profiles**:
```bash
kubectl apply -f - <<EOF
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: data-science-team
spec:
  owner:
    kind: User
    name: datascientist@yourdomain.com
EOF
```

2. **Upload notebook images** to your registry
3. **Configure CI/CD pipelines** for model training
4. **Set up monitoring dashboards**
5. **Backup configuration** regularly

---

## 📚 Additional Resources

- **Kubeflow Documentation**: https://www.kubeflow.org/docs/
- **Troubleshooting Guide**: Check pod logs and events
- **Community**: Kubeflow Slack, GitHub Discussions

This installation gives you a production-grade, multi-tenant Kubeflow deployment with authentication, authorization, and all major ML workflow components. Let me know if you need help with any specific component!




ubuntu@ip-172-31-20-253:~/manifests$ tree .
.
├── CONTRIBUTING.md
├── LICENSE
├── OWNERS
├── README.md
├── SECURITY.md
├── applications
│   ├── admission-webhook
│   │   └── upstream
│   │       ├── base
│   │       │   ├── cluster-role-binding.yaml
│   │       │   ├── cluster-role.yaml
│   │       │   ├── crd.yaml
│   │       │   ├── deployment.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── mutating-webhook-configuration.yaml
│   │       │   ├── params.yaml
│   │       │   ├── service-account.yaml
│   │       │   └── service.yaml
│   │       └── overlays
│   │           └── cert-manager
│   │               ├── certificate.yaml
│   │               ├── deployment.yaml
│   │               ├── kustomization.yaml
│   │               ├── mutating-webhook-configuration.yaml
│   │               └── params.yaml
│   ├── centraldashboard
│   │   ├── overlays
│   │   │   └── oauth2-proxy
│   │   │       └── kustomization.yaml
│   │   └── upstream
│   │       ├── base
│   │       │   ├── clusterrole-binding.yaml
│   │       │   ├── clusterrole.yaml
│   │       │   ├── configmap.yaml
│   │       │   ├── deployment.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── params.env
│   │       │   ├── role-binding.yaml
│   │       │   ├── role.yaml
│   │       │   ├── service-account.yaml
│   │       │   └── service.yaml
│   │       └── overlays
│   │           ├── istio
│   │           │   ├── authorizationpolicy.yaml
│   │           │   ├── kustomization.yaml
│   │           │   ├── params.yaml
│   │           │   └── virtual-service.yaml
│   │           └── kserve
│   │               ├── kustomization.yaml
│   │               └── patches
│   │                   └── configmap.yaml
│   ├── jupyter
│   │   ├── jupyter-web-app
│   │   │   └── upstream
│   │   │       ├── base
│   │   │       │   ├── cluster-role-binding.yaml
│   │   │       │   ├── cluster-role.yaml
│   │   │       │   ├── configs
│   │   │       │   │   ├── logos-configmap.yaml
│   │   │       │   │   └── spawner_ui_config.yaml
│   │   │       │   ├── deployment.yaml
│   │   │       │   ├── kustomization.yaml
│   │   │       │   ├── params.env
│   │   │       │   ├── role-binding.yaml
│   │   │       │   ├── role.yaml
│   │   │       │   ├── service-account.yaml
│   │   │       │   └── service.yaml
│   │   │       └── overlays
│   │   │           └── istio
│   │   │               ├── authorization-policy.yaml
│   │   │               ├── destination-rule.yaml
│   │   │               ├── kustomization.yaml
│   │   │               ├── params.yaml
│   │   │               └── virtual-service.yaml
│   │   └── notebook-controller
│   │       └── upstream
│   │           ├── README.md
│   │           ├── base
│   │           │   └── kustomization.yaml
│   │           ├── crd
│   │           │   ├── bases
│   │           │   │   └── kubeflow.org_notebooks.yaml
│   │           │   ├── kustomization.yaml
│   │           │   ├── kustomizeconfig.yaml
│   │           │   └── patches
│   │           │       ├── cainjection_in_notebooks.yaml
│   │           │       ├── trivial_conversion_patch.yaml
│   │           │       ├── validation_patches.yaml
│   │           │       └── webhook_in_notebooks.yaml
│   │           ├── default
│   │           │   ├── kustomization.yaml
│   │           │   ├── manager_auth_proxy_patch.yaml
│   │           │   ├── manager_image_patch.yaml
│   │           │   ├── manager_prometheus_metrics_patch.yaml
│   │           │   ├── manager_webhook_patch.yaml
│   │           │   └── webhookcainjection_patch.yaml
│   │           ├── manager
│   │           │   ├── kustomization.yaml
│   │           │   ├── manager.yaml
│   │           │   ├── params.env
│   │           │   ├── service-account.yaml
│   │           │   └── service.yaml
│   │           ├── overlays
│   │           │   ├── kubeflow
│   │           │   │   ├── kustomization.yaml
│   │           │   │   └── patches
│   │           │   │       └── remove-namespace.yaml
│   │           │   └── standalone
│   │           │       └── kustomization.yaml
│   │           ├── rbac
│   │           │   ├── auth_proxy_role.yaml
│   │           │   ├── auth_proxy_role_binding.yaml
│   │           │   ├── auth_proxy_service.yaml
│   │           │   ├── kustomization.yaml
│   │           │   ├── leader_election_role.yaml
│   │           │   ├── leader_election_role_binding.yaml
│   │           │   ├── role.yaml
│   │           │   ├── role_binding.yaml
│   │           │   └── user_cluster_roles.yaml
│   │           └── samples
│   │               ├── _v1_notebook.yaml
│   │               ├── _v1alpha1_notebook.yaml
│   │               └── _v1beta1_notebook.yaml
│   ├── katib
│   │   └── upstream
│   │       ├── components
│   │       │   ├── controller
│   │       │   │   ├── controller.yaml
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── rbac.yaml
│   │       │   │   ├── service.yaml
│   │       │   │   └── trial-templates.yaml
│   │       │   ├── crd
│   │       │   │   ├── experiment.yaml
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── suggestion.yaml
│   │       │   │   └── trial.yaml
│   │       │   ├── db-manager
│   │       │   │   ├── db-manager.yaml
│   │       │   │   ├── kustomization.yaml
│   │       │   │   └── service.yaml
│   │       │   ├── mysql
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── mysql.yaml
│   │       │   │   ├── pvc.yaml
│   │       │   │   ├── secret.yaml
│   │       │   │   └── service.yaml
│   │       │   ├── namespace
│   │       │   │   ├── kustomization.yaml
│   │       │   │   └── namespace.yaml
│   │       │   ├── postgres
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── postgres.yaml
│   │       │   │   ├── pvc.yaml
│   │       │   │   ├── secret.yaml
│   │       │   │   └── service.yaml
│   │       │   ├── ui
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── rbac.yaml
│   │       │   │   ├── service.yaml
│   │       │   │   └── ui.yaml
│   │       │   └── webhook
│   │       │       ├── kustomization.yaml
│   │       │       └── webhooks.yaml
│   │       └── installs
│   │           ├── katib-cert-manager
│   │           │   ├── certificate.yaml
│   │           │   ├── katib-config.yaml
│   │           │   ├── kustomization.yaml
│   │           │   ├── params.yaml
│   │           │   └── patches
│   │           │       └── katib-cert-injection.yaml
│   │           ├── katib-external-db
│   │           │   ├── katib-config.yaml
│   │           │   ├── kustomization.yaml
│   │           │   ├── patches
│   │           │   │   └── db-manager.yaml
│   │           │   └── secrets.env
│   │           ├── katib-leader-election
│   │           │   ├── katib-config.yaml
│   │           │   ├── kustomization.yaml
│   │           │   └── leader-election-rbac.yaml
│   │           ├── katib-openshift
│   │           │   ├── katib-config.yaml
│   │           │   ├── kustomization.yaml
│   │           │   └── patches
│   │           │       ├── service-serving-cert.yaml
│   │           │       └── webhook-inject-cabundle.yaml
│   │           ├── katib-standalone
│   │           │   ├── katib-config.yaml
│   │           │   └── kustomization.yaml
│   │           ├── katib-standalone-postgres
│   │           │   ├── katib-config.yaml
│   │           │   ├── kustomization.yaml
│   │           │   └── patches
│   │           │       └── db-manager.yaml
│   │           └── katib-with-kubeflow
│   │               ├── istio-authorizationpolicy.yaml
│   │               ├── kubeflow-katib-roles.yaml
│   │               ├── kustomization.yaml
│   │               ├── params.yaml
│   │               ├── patches
│   │               │   ├── enable-ui-authz-checks.yaml
│   │               │   ├── istio-sidecar-injection.yaml
│   │               │   ├── remove-namespace.yaml
│   │               │   └── ui-rbac.yaml
│   │               └── ui-virtual-service.yaml
│   ├── kserve
│   │   ├── Makefile
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── UPGRADE.md
│   │   ├── assets
│   │   │   ├── kserve.png
│   │   │   └── kserve_new.png
│   │   ├── kserve
│   │   │   ├── aggregated-roles.yaml
│   │   │   ├── kserve-cluster-resources.yaml
│   │   │   ├── kserve.yaml
│   │   │   ├── kserve_kubeflow.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── params.env
│   │   └── models-web-app
│   │       ├── base
│   │       │   ├── deployment.yaml
│   │       │   ├── istio.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── rbac.yaml
│   │       │   └── service.yaml
│   │       └── overlays
│   │           └── kubeflow
│   │               ├── kustomization.yaml
│   │               ├── params.yaml
│   │               ├── patches
│   │               │   ├── web-app-sidecar.yaml
│   │               │   └── web-app-vsvc.yaml
│   │               └── web-app-authorization-policy.yaml
│   ├── model-registry
│   │   └── upstream
│   │       ├── OWNERS
│   │       ├── README.md
│   │       ├── base
│   │       │   ├── kustomization.yaml
│   │       │   ├── model-registry-configmap.yaml
│   │       │   ├── model-registry-deployment.yaml
│   │       │   ├── model-registry-sa.yaml
│   │       │   └── model-registry-service.yaml
│   │       ├── options
│   │       │   ├── controller
│   │       │   │   ├── default
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── manager_metrics_patch.yaml
│   │       │   │   │   └── metrics_service.yaml
│   │       │   │   ├── manager
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   └── manager.yaml
│   │       │   │   ├── network-policy
│   │       │   │   │   ├── allow-metrics-traffic.yaml
│   │       │   │   │   └── kustomization.yaml
│   │       │   │   ├── overlays
│   │       │   │   │   └── base
│   │       │   │   │       ├── kustomization.yaml
│   │       │   │   │       ├── params.env
│   │       │   │   │       └── replacements.yaml
│   │       │   │   ├── prometheus
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   └── monitor.yaml
│   │       │   │   └── rbac
│   │       │   │       ├── kustomization.yaml
│   │       │   │       ├── leader_election_role.yaml
│   │       │   │       ├── leader_election_role_binding.yaml
│   │       │   │       ├── metrics_auth_role.yaml
│   │       │   │       ├── metrics_auth_role_binding.yaml
│   │       │   │       ├── metrics_reader_role.yaml
│   │       │   │       ├── role.yaml
│   │       │   │       ├── role_binding.yaml
│   │       │   │       └── service_account.yaml
│   │       │   ├── csi
│   │       │   │   ├── clusterstoragecontainer.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── istio
│   │       │   │   ├── destination-rule.yaml
│   │       │   │   ├── istio-authorization-policy.yaml
│   │       │   │   ├── kustomization.yaml
│   │       │   │   └── virtual-service.yaml
│   │       │   └── ui
│   │       │       ├── base
│   │       │       │   ├── kustomization.yaml
│   │       │       │   ├── model-registry-ui-deployment.yaml
│   │       │       │   ├── model-registry-ui-role.yaml
│   │       │       │   ├── model-registry-ui-service-account.yaml
│   │       │       │   └── model-registry-ui-service.yaml
│   │       │       └── overlays
│   │       │           ├── integrated
│   │       │           │   ├── kustomization.yaml
│   │       │           │   └── model-registry-ui-deployment.yaml
│   │       │           ├── istio
│   │       │           │   ├── authorization-policy-ui.yaml
│   │       │           │   ├── destination-rule-ui.yaml
│   │       │           │   ├── kustomization.yaml
│   │       │           │   ├── model-registry-ui-service.yaml
│   │       │           │   └── virtual-service.yaml
│   │       │           └── standalone
│   │       │               ├── kubeflow-dashboard-rbac.yaml
│   │       │               ├── kustomization.yaml
│   │       │               └── model-registry-ui-deployment.yaml
│   │       └── overlays
│   │           ├── db
│   │           │   ├── kustomization.yaml
│   │           │   ├── model-registry-db-deployment.yaml
│   │           │   ├── model-registry-db-pvc.yaml
│   │           │   ├── model-registry-db-service.yaml
│   │           │   ├── params.env
│   │           │   ├── patches
│   │           │   │   └── model-registry-deployment.yaml
│   │           │   └── secrets.env
│   │           └── postgres
│   │               ├── kustomization.yaml
│   │               ├── model-registry-db-deployment.yaml
│   │               ├── model-registry-db-pvc.yaml
│   │               ├── model-registry-db-service.yaml
│   │               ├── params.env
│   │               ├── patches
│   │               │   └── model-registry-deployment.yaml
│   │               └── secrets.env
│   ├── pipeline
│   │   └── upstream
│   │       ├── Makefile
│   │       ├── OWNERS
│   │       ├── README.md
│   │       ├── base
│   │       │   ├── application
│   │       │   │   ├── application.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── cache
│   │       │   │   ├── cache-deployment.yaml
│   │       │   │   ├── cache-role.yaml
│   │       │   │   ├── cache-rolebinding.yaml
│   │       │   │   ├── cache-sa.yaml
│   │       │   │   ├── cache-service.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── cache-deployer
│   │       │   │   ├── cache-deployer-deployment.yaml
│   │       │   │   ├── cache-deployer-role.yaml
│   │       │   │   ├── cache-deployer-rolebinding.yaml
│   │       │   │   ├── cluster-scoped
│   │       │   │   │   ├── cache-deployer-clusterrole.yaml
│   │       │   │   │   ├── cache-deployer-clusterrolebinding.yaml
│   │       │   │   │   ├── cache-deployer-sa.yaml
│   │       │   │   │   └── kustomization.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── crds
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── pipelines.kubeflow.org_pipelines.yaml
│   │       │   │   └── pipelines.kubeflow.org_pipelineversions.yaml
│   │       │   ├── installs
│   │       │   │   ├── generic
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── mysql-secret.yaml
│   │       │   │   │   ├── params.yaml
│   │       │   │   │   ├── pipeline-install-config.yaml
│   │       │   │   │   └── postgres
│   │       │   │   │       ├── kustomization.yaml
│   │       │   │   │       ├── params.yaml
│   │       │   │   │       ├── pipeline-install-config.yaml
│   │       │   │   │       └── postgres-secret-extended.yaml
│   │       │   │   └── multi-user
│   │       │   │       ├── api-service
│   │       │   │       │   ├── cluster-role-binding.yaml
│   │       │   │       │   ├── cluster-role.yaml
│   │       │   │       │   ├── deployment-patch.yaml
│   │       │   │       │   ├── kustomization.yaml
│   │       │   │       │   └── params.env
│   │       │   │       ├── cache
│   │       │   │       │   ├── cluster-role-binding.yaml
│   │       │   │       │   ├── cluster-role.yaml
│   │       │   │       │   ├── deployment-patch.yaml
│   │       │   │       │   └── kustomization.yaml
│   │       │   │       ├── istio-authorization-config.yaml
│   │       │   │       ├── kustomization.yaml
│   │       │   │       ├── metadata-writer
│   │       │   │       │   ├── cluster-role-binding.yaml
│   │       │   │       │   ├── cluster-role.yaml
│   │       │   │       │   ├── deployment-patch.yaml
│   │       │   │       │   └── kustomization.yaml
│   │       │   │       ├── params.yaml
│   │       │   │       ├── persistence-agent
│   │       │   │       │   ├── cluster-role-binding.yaml
│   │       │   │       │   ├── cluster-role.yaml
│   │       │   │       │   ├── deployment-patch.yaml
│   │       │   │       │   └── kustomization.yaml
│   │       │   │       ├── pipelines-profile-controller
│   │       │   │       │   ├── decorator-controller.yaml
│   │       │   │       │   ├── deployment.yaml
│   │       │   │       │   ├── kustomization.yaml
│   │       │   │       │   ├── params.env
│   │       │   │       │   ├── requirements-dev.txt
│   │       │   │       │   ├── run_tests.sh
│   │       │   │       │   ├── service.yaml
│   │       │   │       │   ├── sync.py
│   │       │   │       │   └── test_sync.py
│   │       │   │       ├── pipelines-ui
│   │       │   │       │   ├── cluster-role-binding.yaml
│   │       │   │       │   ├── cluster-role.yaml
│   │       │   │       │   ├── configmap-patch.yaml
│   │       │   │       │   ├── deployment-patch.yaml
│   │       │   │       │   └── kustomization.yaml
│   │       │   │       ├── scheduled-workflow
│   │       │   │       │   ├── cluster-role-binding.yaml
│   │       │   │       │   ├── cluster-role.yaml
│   │       │   │       │   ├── deployment-patch.yaml
│   │       │   │       │   └── kustomization.yaml
│   │       │   │       ├── view-edit-cluster-roles.yaml
│   │       │   │       ├── viewer-controller
│   │       │   │       │   ├── cluster-role-binding.yaml
│   │       │   │       │   ├── cluster-role.yaml
│   │       │   │       │   ├── deployment-patch.yaml
│   │       │   │       │   └── kustomization.yaml
│   │       │   │       └── virtual-service.yaml
│   │       │   ├── metadata
│   │       │   │   ├── base
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── metadata-envoy-deployment.yaml
│   │       │   │   │   ├── metadata-envoy-service.yaml
│   │       │   │   │   ├── metadata-grpc-configmap.yaml
│   │       │   │   │   ├── metadata-grpc-deployment.yaml
│   │       │   │   │   ├── metadata-grpc-sa.yaml
│   │       │   │   │   └── metadata-grpc-service.yaml
│   │       │   │   ├── options
│   │       │   │   │   └── istio
│   │       │   │   │       ├── destination-rule.yaml
│   │       │   │   │       ├── istio-authorization-policy.yaml
│   │       │   │   │       ├── kustomization.yaml
│   │       │   │   │       └── virtual-service.yaml
│   │       │   │   └── overlays
│   │       │   │       ├── db
│   │       │   │       │   ├── kustomization.yaml
│   │       │   │       │   ├── metadata-db-deployment.yaml
│   │       │   │       │   ├── metadata-db-pvc.yaml
│   │       │   │       │   ├── metadata-db-service.yaml
│   │       │   │       │   ├── params.env
│   │       │   │       │   ├── patches
│   │       │   │       │   │   └── metadata-grpc-deployment.yaml
│   │       │   │       │   └── secrets.env
│   │       │   │       └── postgres
│   │       │   │           ├── kustomization.yaml
│   │       │   │           ├── metadata-db-deployment.yaml
│   │       │   │           ├── metadata-db-pvc.yaml
│   │       │   │           ├── metadata-db-service.yaml
│   │       │   │           ├── params.env
│   │       │   │           ├── patches
│   │       │   │           │   └── metadata-grpc-deployment.yaml
│   │       │   │           └── secrets.env
│   │       │   ├── pipeline
│   │       │   │   ├── cluster-scoped
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── scheduled-workflow-crd.yaml
│   │       │   │   │   └── viewer-crd.yaml
│   │       │   │   ├── container-builder-sa.yaml
│   │       │   │   ├── kfp-launcher-configmap.yaml
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── metadata-writer
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── metadata-writer-deployment.yaml
│   │       │   │   │   ├── metadata-writer-role.yaml
│   │       │   │   │   ├── metadata-writer-rolebinding.yaml
│   │       │   │   │   └── metadata-writer-sa.yaml
│   │       │   │   ├── ml-pipeline-apiserver-deployment.yaml
│   │       │   │   ├── ml-pipeline-apiserver-role.yaml
│   │       │   │   ├── ml-pipeline-apiserver-rolebinding.yaml
│   │       │   │   ├── ml-pipeline-apiserver-sa.yaml
│   │       │   │   ├── ml-pipeline-apiserver-service.yaml
│   │       │   │   ├── ml-pipeline-persistenceagent-deployment.yaml
│   │       │   │   ├── ml-pipeline-persistenceagent-role.yaml
│   │       │   │   ├── ml-pipeline-persistenceagent-rolebinding.yaml
│   │       │   │   ├── ml-pipeline-persistenceagent-sa.yaml
│   │       │   │   ├── ml-pipeline-scheduledworkflow-deployment.yaml
│   │       │   │   ├── ml-pipeline-scheduledworkflow-role.yaml
│   │       │   │   ├── ml-pipeline-scheduledworkflow-rolebinding.yaml
│   │       │   │   ├── ml-pipeline-scheduledworkflow-sa.yaml
│   │       │   │   ├── ml-pipeline-ui-configmap.yaml
│   │       │   │   ├── ml-pipeline-ui-deployment.yaml
│   │       │   │   ├── ml-pipeline-ui-role.yaml
│   │       │   │   ├── ml-pipeline-ui-rolebinding.yaml
│   │       │   │   ├── ml-pipeline-ui-sa.yaml
│   │       │   │   ├── ml-pipeline-ui-service.yaml
│   │       │   │   ├── ml-pipeline-viewer-crd-deployment.yaml
│   │       │   │   ├── ml-pipeline-viewer-crd-role.yaml
│   │       │   │   ├── ml-pipeline-viewer-crd-rolebinding.yaml
│   │       │   │   ├── ml-pipeline-viewer-crd-sa.yaml
│   │       │   │   ├── ml-pipeline-visualization-deployment.yaml
│   │       │   │   ├── ml-pipeline-visualization-sa.yaml
│   │       │   │   ├── ml-pipeline-visualization-service.yaml
│   │       │   │   ├── pipeline-runner-role.yaml
│   │       │   │   ├── pipeline-runner-rolebinding.yaml
│   │       │   │   ├── pipeline-runner-sa.yaml
│   │       │   │   └── viewer-sa.yaml
│   │       │   ├── postgresql
│   │       │   │   ├── cache
│   │       │   │   │   ├── cache-deployment-patch.yaml
│   │       │   │   │   └── kustomization.yaml
│   │       │   │   └── pipeline
│   │       │   │       ├── kustomization.yaml
│   │       │   │       └── ml-pipeline-apiserver-deployment-patch.yaml
│   │       │   └── webhook
│   │       │       ├── kustomization.yaml
│   │       │       ├── params.yaml
│   │       │       ├── pipelineversion-mutating-webhook-config.yaml
│   │       │       └── pipelineversion-validating-webhook-config.yaml
│   │       ├── cluster-scoped-resources
│   │       │   ├── kustomization.yaml
│   │       │   ├── namespace.yaml
│   │       │   └── params.yaml
│   │       ├── env
│   │       │   ├── aws
│   │       │   │   ├── OWNERS
│   │       │   │   ├── README.md
│   │       │   │   ├── aws-configuration-pipeline-patch.yaml
│   │       │   │   ├── aws-configuration-pipeline-ui-patch.yaml
│   │       │   │   ├── config
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── minio-artifact-secret-patch.env
│   │       │   │   ├── params.env
│   │       │   │   ├── secret.env
│   │       │   │   └── viewer-pod-template.json
│   │       │   ├── azure
│   │       │   │   ├── OWNERS
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── minio-azure-gateway
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── minio-artifact-secret.env
│   │       │   │   │   ├── minio-azure-gateway-deployment.yaml
│   │       │   │   │   └── minio-azure-gateway-service.yaml
│   │       │   │   ├── mysql-secret.env
│   │       │   │   ├── params.env
│   │       │   │   └── readme.md
│   │       │   ├── cert-manager
│   │       │   │   ├── base
│   │       │   │   │   ├── cache-cert-issuer.yaml
│   │       │   │   │   ├── cache-cert.yaml
│   │       │   │   │   ├── cache-webhook-config.yaml
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   └── params.yaml
│   │       │   │   ├── base-webhook-certs
│   │       │   │   │   ├── kfp-api-cert-issuer.yaml
│   │       │   │   │   ├── kfp-api-cert.yaml
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   └── params.yaml
│   │       │   │   ├── cluster-scoped-resources
│   │       │   │   │   └── kustomization.yaml
│   │       │   │   ├── dev
│   │       │   │   │   ├── delete-cache-deployer.yaml
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── namespace.yaml
│   │       │   │   │   └── params.yaml
│   │       │   │   ├── platform-agnostic-k8s-native
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   └── patches
│   │       │   │   │       ├── deployment.yaml
│   │       │   │   │       ├── mutating-webhook.yaml
│   │       │   │   │       ├── service.yaml
│   │       │   │   │       └── validating-webhook.yaml
│   │       │   │   ├── platform-agnostic-multi-user
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   └── patches
│   │       │   │   │       ├── delete.clusterrole.cache-deployer.yaml
│   │       │   │   │       ├── delete.crb.cache-deployer.yaml
│   │       │   │   │       ├── delete.deployment.cache-deployer.yaml
│   │       │   │   │       ├── delete.role.cache-deployer.yaml
│   │       │   │   │       ├── delete.rolebinding.cache-deployer.yaml
│   │       │   │   │       └── delete.sa.cache-deployer.yaml
│   │       │   │   └── platform-agnostic-multi-user-k8s-native
│   │       │   │       ├── kustomization.yaml
│   │       │   │       └── patches
│   │       │   │           ├── deployment.yaml
│   │       │   │           ├── mutating-webhook.yaml
│   │       │   │           ├── service.yaml
│   │       │   │           └── validating-webhook.yaml
│   │       │   ├── dev
│   │       │   │   ├── kustomization.yaml
│   │       │   │   └── postgresql
│   │       │   │       └── kustomization.yaml
│   │       │   ├── dev-kind
│   │       │   │   ├── forward-local-api-endpoint.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── gcp
│   │       │   │   ├── cloudsql-proxy
│   │       │   │   │   ├── cloudsql-proxy-deployment.yaml
│   │       │   │   │   ├── cloudsql-proxy-sa.yaml
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   └── mysql-service.yaml
│   │       │   │   ├── gcp-configurations-patch.yaml
│   │       │   │   ├── inverse-proxy
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── proxy-configmap.yaml
│   │       │   │   │   ├── proxy-deployment.yaml
│   │       │   │   │   ├── proxy-role.yaml
│   │       │   │   │   ├── proxy-rolebinding.yaml
│   │       │   │   │   └── proxy-sa.yaml
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── minio-gcs-gateway
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── minio-artifact-secret.env
│   │       │   │   │   ├── minio-gcs-gateway-deployment.yaml
│   │       │   │   │   ├── minio-gcs-gateway-sa.yaml
│   │       │   │   │   └── minio-gcs-gateway-service.yaml
│   │       │   │   └── params.env
│   │       │   ├── plain
│   │       │   │   └── kustomization.yaml
│   │       │   ├── plain-multi-user
│   │       │   │   └── kustomization.yaml
│   │       │   ├── platform-agnostic
│   │       │   │   └── kustomization.yaml
│   │       │   ├── platform-agnostic-emissary
│   │       │   │   └── kustomization.yaml
│   │       │   ├── platform-agnostic-multi-user
│   │       │   │   └── kustomization.yaml
│   │       │   ├── platform-agnostic-multi-user-emissary
│   │       │   │   └── kustomization.yaml
│   │       │   ├── platform-agnostic-multi-user-legacy
│   │       │   │   └── kustomization.yaml
│   │       │   └── platform-agnostic-postgresql
│   │       │       └── kustomization.yaml
│   │       ├── gcp-workload-identity-setup.sh
│   │       ├── hack
│   │       │   ├── format.sh
│   │       │   ├── presubmit.sh
│   │       │   ├── release.sh
│   │       │   └── test.sh
│   │       ├── sample
│   │       │   ├── README.md
│   │       │   ├── cluster-scoped-resources
│   │       │   │   └── kustomization.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── params-db-secret.env
│   │       │   └── params.env
│   │       ├── third-party
│   │       │   ├── application
│   │       │   │   ├── application-controller-deployment.yaml
│   │       │   │   ├── application-controller-role.yaml
│   │       │   │   ├── application-controller-rolebinding.yaml
│   │       │   │   ├── application-controller-sa.yaml
│   │       │   │   ├── application-controller-service.yaml
│   │       │   │   ├── cluster-scoped
│   │       │   │   │   ├── application-crd.yaml
│   │       │   │   │   └── kustomization.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── argo
│   │       │   │   ├── Kptfile
│   │       │   │   ├── Makefile
│   │       │   │   ├── README.md
│   │       │   │   ├── base
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── params.yaml
│   │       │   │   │   ├── workflow-controller-configmap-patch.yaml
│   │       │   │   │   └── workflow-controller-deployment-patch.yaml
│   │       │   │   ├── installs
│   │       │   │   │   ├── cluster
│   │       │   │   │   │   ├── kustomization.yaml
│   │       │   │   │   │   └── workflow-controller-clusterrolebinding-patch.json
│   │       │   │   │   └── namespace
│   │       │   │   │       ├── cluster-scoped
│   │       │   │   │       │   └── kustomization.yaml
│   │       │   │   │       ├── kustomization.yaml
│   │       │   │   │       └── workflow-controller-deployment-patch.json
│   │       │   │   └── upstream
│   │       │   │       └── manifests
│   │       │   │           ├── Kptfile
│   │       │   │           ├── LICENSE
│   │       │   │           ├── base
│   │       │   │           │   ├── argo-server
│   │       │   │           │   │   ├── argo-server-deployment.yaml
│   │       │   │           │   │   ├── argo-server-sa.yaml
│   │       │   │           │   │   ├── argo-server-service.yaml
│   │       │   │           │   │   └── kustomization.yaml
│   │       │   │           │   ├── crds
│   │       │   │           │   │   ├── full
│   │       │   │           │   │   │   ├── README.md
│   │       │   │           │   │   │   ├── argoproj.io_clusterworkflowtemplates.yaml
│   │       │   │           │   │   │   ├── argoproj.io_cronworkflows.yaml
│   │       │   │           │   │   │   ├── argoproj.io_workflowartifactgctasks.yaml
│   │       │   │           │   │   │   ├── argoproj.io_workfloweventbindings.yaml
│   │       │   │           │   │   │   ├── argoproj.io_workflows.yaml
│   │       │   │           │   │   │   ├── argoproj.io_workflowtaskresults.yaml
│   │       │   │           │   │   │   ├── argoproj.io_workflowtasksets.yaml
│   │       │   │           │   │   │   ├── argoproj.io_workflowtemplates.yaml
│   │       │   │           │   │   │   └── kustomization.yaml
│   │       │   │           │   │   ├── kustomization.yaml
│   │       │   │           │   │   └── minimal
│   │       │   │           │   │       ├── README.md
│   │       │   │           │   │       ├── argoproj.io_clusterworkflowtemplates.yaml
│   │       │   │           │   │       ├── argoproj.io_cronworkflows.yaml
│   │       │   │           │   │       ├── argoproj.io_workflowartifactgctasks.yaml
│   │       │   │           │   │       ├── argoproj.io_workfloweventbindings.yaml
│   │       │   │           │   │       ├── argoproj.io_workflows.yaml
│   │       │   │           │   │       ├── argoproj.io_workflowtaskresults.yaml
│   │       │   │           │   │       ├── argoproj.io_workflowtasksets.yaml
│   │       │   │           │   │       ├── argoproj.io_workflowtemplates.yaml
│   │       │   │           │   │       └── kustomization.yaml
│   │       │   │           │   ├── kustomization.yaml
│   │       │   │           │   └── workflow-controller
│   │       │   │           │       ├── kustomization.yaml
│   │       │   │           │       ├── workflow-controller-configmap.yaml
│   │       │   │           │       ├── workflow-controller-deployment.yaml
│   │       │   │           │       ├── workflow-controller-priorityclass.yaml
│   │       │   │           │       └── workflow-controller-sa.yaml
│   │       │   │           ├── cluster-install
│   │       │   │           │   ├── argo-server-rbac
│   │       │   │           │   │   ├── argo-server-clusterole.yaml
│   │       │   │           │   │   ├── argo-server-clusterolebinding.yaml
│   │       │   │           │   │   └── kustomization.yaml
│   │       │   │           │   ├── kustomization.yaml
│   │       │   │           │   └── workflow-controller-rbac
│   │       │   │           │       ├── kustomization.yaml
│   │       │   │           │       ├── workflow-aggregate-roles.yaml
│   │       │   │           │       ├── workflow-controller-clusterrole.yaml
│   │       │   │           │       ├── workflow-controller-clusterrolebinding.yaml
│   │       │   │           │       ├── workflow-controller-role.yaml
│   │       │   │           │       └── workflow-controller-rolebinding.yaml
│   │       │   │           ├── namespace-install
│   │       │   │           │   ├── argo-server-rbac
│   │       │   │           │   │   ├── argo-server-role.yaml
│   │       │   │           │   │   ├── argo-server-rolebinding.yaml
│   │       │   │           │   │   └── kustomization.yaml
│   │       │   │           │   ├── kustomization.yaml
│   │       │   │           │   ├── overlays
│   │       │   │           │   │   ├── argo-server-deployment.yaml
│   │       │   │           │   │   └── workflow-controller-deployment.yaml
│   │       │   │           │   └── workflow-controller-rbac
│   │       │   │           │       ├── kustomization.yaml
│   │       │   │           │       ├── workflow-controller-role.yaml
│   │       │   │           │       └── workflow-controller-rolebinding.yaml
│   │       │   │           └── quick-start
│   │       │   │               ├── base
│   │       │   │               │   ├── agent-default-rolebinding.yaml
│   │       │   │               │   ├── agent-role.yaml
│   │       │   │               │   ├── argo-server-sso-secret.yaml
│   │       │   │               │   ├── artifact-repositories-configmap.yaml
│   │       │   │               │   ├── artifactgc-default-rolebinding.yaml
│   │       │   │               │   ├── artifactgc-role.yaml
│   │       │   │               │   ├── cluster-workflow-template-rbac.yaml
│   │       │   │               │   ├── default.service-account-token-secret.yaml
│   │       │   │               │   ├── executor
│   │       │   │               │   │   ├── docker
│   │       │   │               │   │   │   └── executor-role.yaml
│   │       │   │               │   │   ├── emissary
│   │       │   │               │   │   │   └── executor-role.yaml
│   │       │   │               │   │   ├── k8sapi
│   │       │   │               │   │   │   └── executor-role.yaml
│   │       │   │               │   │   ├── kubelet
│   │       │   │               │   │   │   ├── executor-role.yaml
│   │       │   │               │   │   │   ├── kubelet-executor-clusterrole.yaml
│   │       │   │               │   │   │   └── kubelet-executor-default-clusterrolebinding.yaml
│   │       │   │               │   │   └── pns
│   │       │   │               │   │       └── executor-role.yaml
│   │       │   │               │   ├── executor-default-rolebinding.yaml
│   │       │   │               │   ├── httpbin
│   │       │   │               │   │   ├── httpbin-deploy.yaml
│   │       │   │               │   │   ├── httpbin-service.yaml
│   │       │   │               │   │   ├── kustomization.yaml
│   │       │   │               │   │   └── my-httpbin-cred-secret.yaml
│   │       │   │               │   ├── kustomization.yaml
│   │       │   │               │   ├── memoizer-default-rolebinding.yaml
│   │       │   │               │   ├── memoizer-role.yaml
│   │       │   │               │   ├── minio
│   │       │   │               │   │   ├── kustomization.yaml
│   │       │   │               │   │   ├── minio-deploy.yaml
│   │       │   │               │   │   ├── minio-service.yaml
│   │       │   │               │   │   └── my-minio-cred-secret.yaml
│   │       │   │               │   ├── overlays
│   │       │   │               │   │   ├── argo-server-deployment.yaml
│   │       │   │               │   │   └── workflow-controller-configmap.yaml
│   │       │   │               │   ├── pod-manager-default-rolebinding.yaml
│   │       │   │               │   ├── pod-manager-role.yaml
│   │       │   │               │   ├── prometheus
│   │       │   │               │   │   ├── kustomization.yaml
│   │       │   │               │   │   ├── prometheus-config-cluster.yaml
│   │       │   │               │   │   ├── prometheus-deployment.yaml
│   │       │   │               │   │   └── prometheus-service.yaml
│   │       │   │               │   ├── webhooks
│   │       │   │               │   │   ├── argo-workflows-webhook-clients-secret.yaml
│   │       │   │               │   │   ├── github.com-rolebinding.yaml
│   │       │   │               │   │   ├── github.com-sa.yaml
│   │       │   │               │   │   ├── github.com-secret.yaml
│   │       │   │               │   │   ├── kustomization.yaml
│   │       │   │               │   │   └── submit-workflow-template-role.yaml
│   │       │   │               │   ├── workflow-default-rolebinding.yaml
│   │       │   │               │   ├── workflow-manager-default-rolebinding.yaml
│   │       │   │               │   └── workflow-manager-role.yaml
│   │       │   │               ├── minimal
│   │       │   │               │   ├── kustomization.yaml
│   │       │   │               │   └── overlays
│   │       │   │               │       └── workflow-controller-configmap.yaml
│   │       │   │               ├── mysql
│   │       │   │               │   ├── argo-mysql-config-secret.yaml
│   │       │   │               │   ├── kustomization.yaml
│   │       │   │               │   ├── mysql-deployment.yaml
│   │       │   │               │   ├── mysql-service.yaml
│   │       │   │               │   └── overlays
│   │       │   │               │       └── workflow-controller-configmap.yaml
│   │       │   │               ├── postgres
│   │       │   │               │   ├── argo-postgres-config-secret.yaml
│   │       │   │               │   ├── kustomization.yaml
│   │       │   │               │   ├── overlays
│   │       │   │               │   │   └── workflow-controller-configmap.yaml
│   │       │   │               │   ├── postgres-deployment.yaml
│   │       │   │               │   └── postgres-service.yaml
│   │       │   │               └── sso
│   │       │   │                   ├── dex
│   │       │   │                   │   ├── dev-svc.yaml
│   │       │   │                   │   ├── dex-cm.yaml
│   │       │   │                   │   ├── dex-deploy.yaml
│   │       │   │                   │   ├── dex-rb.yaml
│   │       │   │                   │   ├── dex-role.yaml
│   │       │   │                   │   ├── dex-sa.yaml
│   │       │   │                   │   └── kustomization.yaml
│   │       │   │                   ├── kustomization.yaml
│   │       │   │                   └── overlays
│   │       │   │                       ├── argo-server-sa.yaml
│   │       │   │                       └── workflow-controller-configmap.yaml
│   │       │   ├── grafana
│   │       │   │   ├── grafana-deployment.yaml
│   │       │   │   ├── grafana-role.yaml
│   │       │   │   ├── grafana-rolebinding.yaml
│   │       │   │   ├── grafana-sa.yaml
│   │       │   │   ├── grafana-service.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── metacontroller
│   │       │   │   └── base
│   │       │   │       ├── cluster-role-binding.yaml
│   │       │   │       ├── cluster-role.yaml
│   │       │   │       ├── crd.yaml
│   │       │   │       ├── kustomization.yaml
│   │       │   │       ├── service-account.yaml
│   │       │   │       └── stateful-set.yaml
│   │       │   ├── minio
│   │       │   │   ├── base
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── minio-deployment.yaml
│   │       │   │   │   ├── minio-pvc.yaml
│   │       │   │   │   ├── minio-service.yaml
│   │       │   │   │   └── mlpipeline-minio-artifact-secret.yaml
│   │       │   │   └── options
│   │       │   │       └── istio
│   │       │   │           ├── istio-authorization-policy.yaml
│   │       │   │           └── kustomization.yaml
│   │       │   ├── mysql
│   │       │   │   ├── base
│   │       │   │   │   ├── kustomization.yaml
│   │       │   │   │   ├── mysql-deployment.yaml
│   │       │   │   │   ├── mysql-pv-claim.yaml
│   │       │   │   │   ├── mysql-service.yaml
│   │       │   │   │   └── mysql-serviceaccount.yaml
│   │       │   │   └── options
│   │       │   │       └── istio
│   │       │   │           ├── istio-authorization-policy.yaml
│   │       │   │           └── kustomization.yaml
│   │       │   ├── postgresql
│   │       │   │   ├── README.md
│   │       │   │   └── base
│   │       │   │       ├── kustomization.yaml
│   │       │   │       ├── pg-deployment.yaml
│   │       │   │       ├── pg-pvc.yaml
│   │       │   │       ├── pg-secret.yaml
│   │       │   │       ├── pg-service.yaml
│   │       │   │       └── pg-serviceaccount.yaml
│   │       │   └── prometheus
│   │       │       ├── kustomization.yaml
│   │       │       ├── prometheus-configmap.yaml
│   │       │       ├── prometheus-deployment.yaml
│   │       │       ├── prometheus-role.yaml
│   │       │       ├── prometheus-rolebinding.yaml
│   │       │       ├── prometheus-sa.yaml
│   │       │       └── prometheus-service.yaml
│   │       └── wi-utils.sh
│   ├── profiles
│   │   ├── pss
│   │   │   ├── kustomization.yaml
│   │   │   └── namespace-labels.yaml
│   │   └── upstream
│   │       ├── README.md
│   │       ├── base
│   │       │   ├── kustomization.yaml
│   │       │   ├── namespace-labels.yaml
│   │       │   └── patches
│   │       │       └── manager.yaml
│   │       ├── crd
│   │       │   ├── bases
│   │       │   │   └── kubeflow.org_profiles.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── kustomizeconfig.yaml
│   │       │   └── patches
│   │       │       ├── cainjection_in_profiles.yaml
│   │       │       ├── trivial_conversion_patch.yaml
│   │       │       └── webhook_in_profiles.yaml
│   │       ├── default
│   │       │   ├── kustomization.yaml
│   │       │   ├── manager_auth_proxy_patch.yaml
│   │       │   ├── manager_prometheus_metrics_patch.yaml
│   │       │   ├── manager_webhook_patch.yaml
│   │       │   └── webhookcainjection_patch.yaml
│   │       ├── manager
│   │       │   ├── kustomization.yaml
│   │       │   ├── manager.yaml
│   │       │   └── service-account.yaml
│   │       ├── overlays
│   │       │   ├── kubeflow
│   │       │   │   ├── authorizationpolicy.yaml
│   │       │   │   ├── kustomization.yaml
│   │       │   │   ├── params.yaml
│   │       │   │   ├── patches
│   │       │   │   │   ├── kfam.yaml
│   │       │   │   │   └── remove-namespace.yaml
│   │       │   │   ├── service.yaml
│   │       │   │   └── virtual-service.yaml
│   │       │   └── standalone
│   │       │       └── kustomization.yaml
│   │       ├── prometheus
│   │       │   ├── kustomization.yaml
│   │       │   └── monitor.yaml
│   │       ├── rbac
│   │       │   ├── auth_proxy_client_clusterrole.yaml
│   │       │   ├── auth_proxy_role.yaml
│   │       │   ├── auth_proxy_role_binding.yaml
│   │       │   ├── auth_proxy_service.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── leader_election_role.yaml
│   │       │   ├── leader_election_role_binding.yaml
│   │       │   ├── profile_editor_role.yaml
│   │       │   ├── profile_viewer_role.yaml
│   │       │   ├── role.yaml
│   │       │   ├── role_binding.yaml
│   │       │   └── service_account.yaml
│   │       └── samples
│   │           ├── _v1_profile.yaml
│   │           ├── _v1_profile_aws_iam.yaml
│   │           └── _v1beta1_profile.yaml
│   ├── pvcviewer-controller
│   │   └── upstream
│   │       ├── base
│   │       │   └── kustomization.yaml
│   │       ├── certmanager
│   │       │   ├── certificate.yaml
│   │       │   ├── kustomization.yaml
│   │       │   └── kustomizeconfig.yaml
│   │       ├── crd
│   │       │   ├── bases
│   │       │   │   └── kubeflow.org_pvcviewers.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── kustomizeconfig.yaml
│   │       │   └── patches
│   │       │       ├── cainjection_in_pvcviewers.yaml
│   │       │       └── webhook_in_pvcviewers.yaml
│   │       ├── default
│   │       │   ├── cainjection_patch.yaml
│   │       │   ├── dnsnames_patch.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── kustomizeconfig.yaml
│   │       │   ├── manager_auth_proxy_patch.yaml
│   │       │   ├── manager_webhook_patch.yaml
│   │       │   └── remove_namespace.yaml
│   │       ├── manager
│   │       │   ├── kustomization.yaml
│   │       │   └── manager.yaml
│   │       ├── prometheus
│   │       │   ├── kustomization.yaml
│   │       │   └── monitor.yaml
│   │       ├── rbac
│   │       │   ├── auth_proxy_client_clusterrole.yaml
│   │       │   ├── auth_proxy_role.yaml
│   │       │   ├── auth_proxy_role_binding.yaml
│   │       │   ├── auth_proxy_service.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── leader_election_role.yaml
│   │       │   ├── leader_election_role_binding.yaml
│   │       │   ├── role.yaml
│   │       │   ├── role_binding.yaml
│   │       │   ├── service_account.yaml
│   │       │   ├── volumesviewer_editor_role.yaml
│   │       │   └── volumesviewer_viewer_role.yaml
│   │       ├── samples
│   │       │   ├── _v1alpha1_pvcviewer.yaml
│   │       │   └── kustomization.yaml
│   │       └── webhook
│   │           ├── kustomization.yaml
│   │           ├── kustomizeconfig.yaml
│   │           ├── manifests.yaml
│   │           └── service.yaml
│   ├── spark
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── spark-operator
│   │   │   ├── base
│   │   │   │   ├── aggregated-roles.yaml
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── resources.yaml
│   │   │   └── overlays
│   │   │       ├── kubeflow
│   │   │       │   └── kustomization.yaml
│   │   │       └── standalone
│   │   │           └── kustomization.yaml
│   │   └── sparkapplication_example.yaml
│   ├── tensorboard
│   │   ├── tensorboard-controller
│   │   │   └── upstream
│   │   │       ├── base
│   │   │       │   ├── kustomization.yaml
│   │   │       │   ├── patches
│   │   │       │   │   ├── add_controller_config.yaml
│   │   │       │   │   └── add_service_account.yaml
│   │   │       │   └── service_account.yaml
│   │   │       ├── certmanager
│   │   │       │   ├── certificate.yaml
│   │   │       │   ├── kustomization.yaml
│   │   │       │   └── kustomizeconfig.yaml
│   │   │       ├── crd
│   │   │       │   ├── bases
│   │   │       │   │   └── tensorboard.kubeflow.org_tensorboards.yaml
│   │   │       │   ├── kustomization.yaml
│   │   │       │   ├── kustomizeconfig.yaml
│   │   │       │   └── patches
│   │   │       │       ├── cainjection_in_tensorboards.yaml
│   │   │       │       └── webhook_in_tensorboards.yaml
│   │   │       ├── default
│   │   │       │   ├── kustomization.yaml
│   │   │       │   ├── manager_auth_proxy_patch.yaml
│   │   │       │   ├── manager_prometheus_metrics_patch.yaml
│   │   │       │   ├── manager_webhook_patch.yaml
│   │   │       │   └── webhookcainjection_patch.yaml
│   │   │       ├── manager
│   │   │       │   ├── controller_manager_config.yaml
│   │   │       │   ├── kustomization.yaml
│   │   │       │   └── manager.yaml
│   │   │       ├── overlays
│   │   │       │   ├── kubeflow
│   │   │       │   │   ├── kustomization.yaml
│   │   │       │   │   └── patches
│   │   │       │   │       └── remove-namespace.yaml
│   │   │       │   └── standalone
│   │   │       │       └── kustomization.yaml
│   │   │       ├── prometheus
│   │   │       │   ├── kustomization.yaml
│   │   │       │   └── monitor.yaml
│   │   │       ├── rbac
│   │   │       │   ├── auth_proxy_client_clusterrole.yaml
│   │   │       │   ├── auth_proxy_role.yaml
│   │   │       │   ├── auth_proxy_role_binding.yaml
│   │   │       │   ├── auth_proxy_service.yaml
│   │   │       │   ├── kustomization.yaml
│   │   │       │   ├── leader_election_role.yaml
│   │   │       │   ├── leader_election_role_binding.yaml
│   │   │       │   ├── role.yaml
│   │   │       │   ├── role_binding.yaml
│   │   │       │   └── service_account.yaml
│   │   │       ├── samples
│   │   │       │   └── tensorboard_v1alpha1_tensorboard.yaml
│   │   │       └── webhook
│   │   │           ├── kustomization.yaml
│   │   │           ├── kustomizeconfig.yaml
│   │   │           ├── manifests.yaml
│   │   │           └── service.yaml
│   │   └── tensorboards-web-app
│   │       └── upstream
│   │           ├── base
│   │           │   ├── cluster-role-binding.yaml
│   │           │   ├── cluster-role.yaml
│   │           │   ├── deployment.yaml
│   │           │   ├── kustomization.yaml
│   │           │   ├── params.env
│   │           │   ├── service-account.yaml
│   │           │   └── service.yaml
│   │           └── overlays
│   │               └── istio
│   │                   ├── authorization-policy.yaml
│   │                   ├── destination-rule.yaml
│   │                   ├── kustomization.yaml
│   │                   ├── params.yaml
│   │                   └── virtual-service.yaml
│   ├── training-operator
│   │   └── upstream
│   │       ├── base
│   │       │   ├── crds
│   │       │   │   ├── kubeflow.org_jaxjobs.yaml
│   │       │   │   ├── kubeflow.org_mpijobs.yaml
│   │       │   │   ├── kubeflow.org_paddlejobs.yaml
│   │       │   │   ├── kubeflow.org_pytorchjobs.yaml
│   │       │   │   ├── kubeflow.org_tfjobs.yaml
│   │       │   │   ├── kubeflow.org_xgboostjobs.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   ├── deployment.yaml
│   │       │   ├── kustomization.yaml
│   │       │   ├── rbac
│   │       │   │   ├── cluster-role-binding.yaml
│   │       │   │   ├── role.yaml
│   │       │   │   └── service-account.yaml
│   │       │   ├── service.yaml
│   │       │   └── webhook
│   │       │       ├── kustomization.yaml
│   │       │       ├── kustomizeconfig.yaml
│   │       │       ├── manifests.yaml
│   │       │       └── patch.yaml
│   │       ├── overlays
│   │       │   ├── kubeflow
│   │       │   │   ├── kubeflow-training-roles.yaml
│   │       │   │   └── kustomization.yaml
│   │       │   └── standalone
│   │       │       ├── kustomization.yaml
│   │       │       └── namespace.yaml
│   │       └── v2
│   │           ├── base
│   │           │   ├── crds
│   │           │   │   ├── kubeflow.org_clustertrainingruntimes.yaml
│   │           │   │   ├── kubeflow.org_trainingruntimes.yaml
│   │           │   │   ├── kubeflow.org_trainjobs.yaml
│   │           │   │   └── kustomization.yaml
│   │           │   ├── manager
│   │           │   │   ├── kustomization.yaml
│   │           │   │   └── manager.yaml
│   │           │   ├── rbac
│   │           │   │   ├── kustomization.yaml
│   │           │   │   ├── role.yaml
│   │           │   │   ├── role_binding.yaml
│   │           │   │   └── service_account.yaml
│   │           │   ├── runtimes
│   │           │   │   └── pre-training
│   │           │   │       ├── kustomization.yaml
│   │           │   │       └── torch-distributed.yaml
│   │           │   └── webhook
│   │           │       ├── kustomization.yaml
│   │           │       ├── kustomizeconfig.yaml
│   │           │       ├── manifests.yaml
│   │           │       └── patch.yaml
│   │           └── overlays
│   │               ├── only-manager
│   │               │   ├── kustomization.yaml
│   │               │   └── namespace.yaml
│   │               ├── only-runtimes
│   │               │   └── kustomization.yaml
│   │               └── standalone
│   │                   ├── kustomization.yaml
│   │                   └── namespace.yaml
│   └── volumes-web-app
│       └── upstream
│           ├── base
│           │   ├── cluster-role-binding.yaml
│           │   ├── cluster-role.yaml
│           │   ├── deployment.yaml
│           │   ├── kustomization.yaml
│           │   ├── params.env
│           │   ├── service-account.yaml
│           │   ├── service.yaml
│           │   └── viewer-spec.yaml
│           └── overlays
│               └── istio
│                   ├── authorization-policy.yaml
│                   ├── destination-rule.yaml
│                   ├── kustomization.yaml
│                   ├── params.yaml
│                   └── virtual-service.yaml
├── common
│   ├── cert-manager
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── base
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace-patch.yaml
│   │   │   └── upstream
│   │   │       └── cert-manager.yaml
│   │   └── kubeflow-issuer
│   │       └── base
│   │           ├── cluster-issuer.yaml
│   │           └── kustomization.yaml
│   ├── dex
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── base
│   │   │   ├── config-map.yaml
│   │   │   ├── crds.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── dex-passwords.yaml
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml
│   │   │   ├── secret_params.env
│   │   │   └── service.yaml
│   │   └── overlays
│   │       ├── istio
│   │       │   ├── kustomization.yaml
│   │       │   └── virtual-service.yaml
│   │       └── oauth2-proxy
│   │           ├── config-map.yaml
│   │           └── kustomization.yaml
│   ├── istio
│   │   ├── README.md
│   │   ├── cluster-local-gateway
│   │   │   ├── README.md
│   │   │   └── base
│   │   │       ├── cluster-local-gateway.yaml
│   │   │       ├── gateway-authorizationpolicy.yaml
│   │   │       ├── gateway.yaml
│   │   │       ├── kustomization.yaml
│   │   │       └── patches
│   │   │           └── remove-pdb.yaml
│   │   ├── istio-crds
│   │   │   └── base
│   │   │       ├── crd.yaml
│   │   │       └── kustomization.yaml
│   │   ├── istio-install
│   │   │   ├── base
│   │   │   │   ├── deny_all_authorizationpolicy.yaml
│   │   │   │   ├── gateway.yaml
│   │   │   │   ├── gateway_authorizationpolicy.yaml
│   │   │   │   ├── install.yaml
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── patches
│   │   │   │       ├── disable-debugging.yaml
│   │   │   │       ├── istio-configmap-disable-tracing.yaml
│   │   │   │       ├── istio-ingressgateway-remove-pdb.yaml
│   │   │   │       ├── istiod-remove-pdb.yaml
│   │   │   │       ├── seccomp-istio-ingressgateway.yaml
│   │   │   │       ├── seccomp-istiod.yaml
│   │   │   │       └── service.yaml
│   │   │   └── overlays
│   │   │       ├── gke
│   │   │       │   ├── gke-cni-patch.yaml
│   │   │       │   └── kustomization.yaml
│   │   │       ├── insecure
│   │   │       │   ├── configmap-patch.yaml
│   │   │       │   ├── kustomization.yaml
│   │   │       │   └── namespaces-pss-privileged.yaml
│   │   │       └── oauth2-proxy
│   │   │           └── kustomization.yaml
│   │   ├── istio-namespace
│   │   │   └── base
│   │   │       ├── kustomization.yaml
│   │   │       └── namespace.yaml
│   │   ├── kubeflow-istio-resources
│   │   │   └── base
│   │   │       ├── cluster-roles.yaml
│   │   │       ├── kf-istio-resources.yaml
│   │   │       └── kustomization.yaml
│   │   ├── profile-overlay.yaml
│   │   ├── profile.yaml
│   │   └── split-istio-packages
│   ├── knative
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── knative-eventing
│   │   │   └── base
│   │   │       ├── kustomization.yaml
│   │   │       ├── patches
│   │   │       │   └── clusterrole-patch.yaml
│   │   │       └── upstream
│   │   │           ├── eventing-core.yaml
│   │   │           ├── in-memory-channel.yaml
│   │   │           └── mt-channel-broker.yaml
│   │   ├── knative-eventing-post-install-jobs
│   │   │   └── base
│   │   │       ├── eventing-post-install.yaml
│   │   │       └── kustomization.yaml
│   │   ├── knative-serving
│   │   │   ├── base
│   │   │   │   ├── istio-authorization-policy.yaml
│   │   │   │   ├── kustomization.yaml
│   │   │   │   ├── patches
│   │   │   │   │   ├── config-deployment.yaml
│   │   │   │   │   ├── config-istio.yaml
│   │   │   │   │   ├── knative-serving-namespaced-admin.yaml
│   │   │   │   │   ├── knative-serving-namespaced-edit.yaml
│   │   │   │   │   ├── knative-serving-namespaced-view.yaml
│   │   │   │   │   ├── namespace-injection.yaml
│   │   │   │   │   ├── remove-gateway.yaml
│   │   │   │   │   ├── seccomp.yaml
│   │   │   │   │   ├── service-labels.yaml
│   │   │   │   │   └── sidecar-injection.yaml
│   │   │   │   └── upstream
│   │   │   │       ├── net-istio.yaml
│   │   │   │       └── serving-core.yaml
│   │   │   └── overlays
│   │   │       └── gateways
│   │   │           ├── kustomization.yaml
│   │   │           └── patches
│   │   │               ├── config-domain.yaml
│   │   │               ├── gateway-selector-in-istio-system.yaml
│   │   │               └── gateway-selector-in-knative-serving.yaml
│   │   └── knative-serving-post-install-jobs
│   │       └── base
│   │           ├── kustomization.yaml
│   │           └── serving-post-install-jobs.yaml
│   ├── kubeflow-namespace
│   │   └── base
│   │       ├── kustomization.yaml
│   │       └── namespace.yaml
│   ├── kubeflow-roles
│   │   ├── OWNERS
│   │   ├── README.md
│   │   └── base
│   │       ├── cluster-roles.yaml
│   │       └── kustomization.yaml
│   ├── networkpolicies
│   │   ├── OWNERS
│   │   ├── README.md
│   │   └── base
│   │       ├── cache-server.yaml
│   │       ├── centraldashboard.yaml
│   │       ├── default-allow-same-namespace.yaml
│   │       ├── jupyter-web-app.yaml
│   │       ├── katib-controller.yaml
│   │       ├── katib-db-manager.yaml
│   │       ├── katib-ui.yaml
│   │       ├── kserve-models-web-app.yaml
│   │       ├── kserve.yaml
│   │       ├── kustomization.yaml
│   │       ├── metadata-envoy.yaml
│   │       ├── metadata-grpc-server.yaml
│   │       ├── minio.yaml
│   │       ├── ml-pipeline-ui.yaml
│   │       ├── ml-pipeline.yaml
│   │       ├── model-registry-ui.yaml
│   │       ├── model-registry.yaml
│   │       ├── poddefaults.yaml
│   │       ├── pvcviewer-webhook.yaml
│   │       ├── spark-operator-webhook.yaml
│   │       ├── tensorboards-web-app.yaml
│   │       ├── training-operator-webhook.yaml
│   │       └── volumes-web-app.yaml
│   ├── oauth2-proxy
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── base
│   │   │   ├── README.md
│   │   │   ├── deployment.yaml
│   │   │   ├── kubeflow-logo.svg
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml
│   │   │   ├── oauth2_proxy.cfg
│   │   │   ├── service.yaml
│   │   │   ├── serviceaccount.yaml
│   │   │   └── virtualservice.yaml
│   │   ├── components
│   │   │   ├── README.md
│   │   │   ├── allow-unauthenticated-issuer-discovery
│   │   │   │   ├── README.md
│   │   │   │   ├── clusterrolebinding.unauthenticated-oidc-viewer.yaml
│   │   │   │   └── kustomization.yaml
│   │   │   ├── central-dashboard
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── patches
│   │   │   │       └── deployment.logout-url.yaml
│   │   │   ├── cluster-jwks-proxy
│   │   │   │   ├── README.md
│   │   │   │   ├── cluster-jwks-proxy.yaml
│   │   │   │   └── kustomization.yaml
│   │   │   ├── istio-external-auth
│   │   │   │   ├── README.md
│   │   │   │   ├── authorizationpolicy.istio-ingressgateway-oauth2-proxy.cloudflare.yaml
│   │   │   │   ├── authorizationpolicy.istio-ingressgateway-oauth2-proxy.yaml
│   │   │   │   ├── authorizationpolicy.istio-ingressgateway-require-jwt.cloudflare.yaml
│   │   │   │   ├── authorizationpolicy.istio-ingressgateway-require-jwt.yaml
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── requestauthentication.dex-jwt.yaml
│   │   │   ├── istio-external-auth-patches
│   │   │   │   ├── README.md
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── patches
│   │   │   │       ├── cm.enable-oauth2-proxy.yaml
│   │   │   │       └── deployment.jwt-refresh-interval.yaml
│   │   │   ├── istio-m2m
│   │   │   │   ├── README.md
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── requestauthentication.yaml
│   │   │   ├── kubeflow_auth_diagram.svg
│   │   │   └── oauth2-flow.svg
│   │   └── overlays
│   │       ├── m2m-dex-and-eks
│   │       │   └── kustomization.yaml
│   │       ├── m2m-dex-and-kind
│   │       │   └── kustomization.yaml
│   │       └── m2m-dex-only
│   │           └── kustomization.yaml
│   └── user-namespace
│       └── base
│           ├── kustomization.yaml
│           ├── params.env
│           ├── params.yaml
│           └── profile-instance.yaml
├── example
│   └── kustomization.yaml
├── experimental
│   ├── OWNERS
│   ├── README.md
│   ├── helm
│   │   └── charts
│   │       └── model-registry
│   │           ├── Chart.yaml
│   │           ├── README.md
│   │           ├── ci
│   │           │   ├── ci-values.yaml
│   │           │   ├── values-controller-full.yaml
│   │           │   ├── values-controller-manager.yaml
│   │           │   ├── values-controller-network-policy.yaml
│   │           │   ├── values-controller-prometheus.yaml
│   │           │   ├── values-controller-rbac.yaml
│   │           │   ├── values-controller.yaml
│   │           │   ├── values-csi.yaml
│   │           │   ├── values-db.yaml
│   │           │   ├── values-istio.yaml
│   │           │   ├── values-postgres.yaml
│   │           │   ├── values-production.yaml
│   │           │   ├── values-standalone.yaml
│   │           │   ├── values-ui-integrated.yaml
│   │           │   ├── values-ui-istio.yaml
│   │           │   ├── values-ui-standalone.yaml
│   │           │   └── values-ui.yaml
│   │           ├── templates
│   │           │   ├── _helpers.tpl
│   │           │   ├── controller
│   │           │   │   ├── deployment.yaml
│   │           │   │   ├── metrics-service.yaml
│   │           │   │   └── service.yaml
│   │           │   ├── database
│   │           │   │   ├── mysql
│   │           │   │   │   ├── configmap.yaml
│   │           │   │   │   ├── deployment.yaml
│   │           │   │   │   ├── pvc.yaml
│   │           │   │   │   ├── secret.yaml
│   │           │   │   │   └── service.yaml
│   │           │   │   └── postgres
│   │           │   │       ├── configmap.yaml
│   │           │   │       ├── deployment.yaml
│   │           │   │       ├── pvc.yaml
│   │           │   │       ├── secret.yaml
│   │           │   │       └── service.yaml
│   │           │   ├── istio
│   │           │   │   ├── authorizationpolicy.yaml
│   │           │   │   ├── destinationrule.yaml
│   │           │   │   └── virtualservice.yaml
│   │           │   ├── monitoring
│   │           │   │   └── servicemonitor.yaml
│   │           │   ├── rbac
│   │           │   │   └── controller-rbac.yaml
│   │           │   ├── security
│   │           │   │   ├── clusterstoragecontainer.yaml
│   │           │   │   └── networkpolicy.yaml
│   │           │   ├── server
│   │           │   │   ├── configmap.yaml
│   │           │   │   ├── deployment.yaml
│   │           │   │   ├── service.yaml
│   │           │   │   └── serviceaccount.yaml
│   │           │   └── ui
│   │           │       ├── dashboard-rbac.yaml
│   │           │       ├── deployment.yaml
│   │           │       ├── istio-authorizationpolicy.yaml
│   │           │       ├── istio-destinationrule.yaml
│   │           │       ├── istio-virtualservice.yaml
│   │           │       ├── rbac.yaml
│   │           │       ├── service.yaml
│   │           │       └── serviceaccount.yaml
│   │           └── values.yaml
│   ├── ray
│   │   ├── Makefile
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── UPGRADE.md
│   │   ├── assets
│   │   │   ├── architecture.svg
│   │   │   └── map-of-ray.png
│   │   ├── kuberay-operator
│   │   │   ├── base
│   │   │   │   ├── aggregated-roles.yaml
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── resources.yaml
│   │   │   └── overlays
│   │   │       ├── kubeflow
│   │   │       │   ├── disable-injection.yaml
│   │   │       │   └── kustomization.yaml
│   │   │       └── standalone
│   │   │           └── kustomization.yaml
│   │   ├── raycluster_example.yaml
│   │   └── test.sh
│   ├── seaweedfs
│   │   ├── OWNERS
│   │   ├── README.md
│   │   ├── UPDGRADE.md
│   │   ├── base
│   │   │   ├── argo-workflow-controller
│   │   │   │   └── workflow-controller-configmap-patch.yaml
│   │   │   ├── kustomization.yaml
│   │   │   ├── minio-service-patch.yaml
│   │   │   ├── pipeline-profile-controller
│   │   │   │   ├── deployment.yaml
│   │   │   │   └── sync.py
│   │   │   └── seaweedfs
│   │   │       ├── kustomization.yaml
│   │   │       ├── seaweedfs-create-admin-user-job.yaml
│   │   │       ├── seaweedfs-deployment.yaml
│   │   │       ├── seaweedfs-networkpolicy.yaml
│   │   │       ├── seaweedfs-pvc.yaml
│   │   │       ├── seaweedfs-service-account.yaml
│   │   │       └── seaweedfs-service.yaml
│   │   ├── istio
│   │   │   ├── istio-authorization-policy.yaml
│   │   │   └── kustomization.yaml
│   │   └── test.sh
│   └── security
│       └── PSS
│           └── dynamic
│               └── restricted
│                   ├── kustomization.yaml
│                   └── namespace-labels.yaml
├── proposals
│   ├── 20200913-rootlessKubeflow.md
│   ├── 20220926-contrib-component-guidelines.md
│   ├── 20230323-end-to-end-testing.md
│   ├── 20240606-jwt-handling.md
│   └── README.md
├── scripts
│   ├── library.sh
│   ├── synchronize-istio-manifests.sh
│   ├── synchronize-katib-manifests.sh
│   ├── synchronize-knative-manifests.sh
│   ├── synchronize-kserve-kserve-manifests.sh
│   ├── synchronize-kserve-web-application-manifests.sh
│   ├── synchronize-kubeflow-manifests.sh
│   ├── synchronize-model-registry-manifests.sh
│   ├── synchronize-pipelines-manifests.sh
│   ├── synchronize-spark-operator-manifests.sh
│   ├── synchronize-training-operator-manifests.sh
│   └── template.sh
└── tests
    ├── PSS_baseline_enable.sh
    ├── PSS_restricted_enable.sh
    ├── README.md
    ├── argo_cli_install.sh
    ├── central_dashboard_install.sh
    ├── cert_manager_install.sh
    ├── dex_install.sh
    ├── dex_login_test.py
    ├── helm_compare_all_scenarios.sh
    ├── helm_compare_manifests.py
    ├── helm_kustomize_compare.sh
    ├── install_KinD_create_KinD_cluster_install_kustomize.sh
    ├── istio-cni_install.sh
    ├── katib_install.sh
    ├── katib_test.yaml
    ├── knative-cni_install.sh
    ├── kserve
    │   ├── data
    │   │   └── iris_input.json
    │   ├── requirements.txt
    │   ├── test_sklearn.py
    │   └── utils.py
    ├── kserve_install.sh
    ├── kserve_test.sh
    ├── kserve_test.yaml
    ├── kubectl_install.sh
    ├── kubeflow_profile_install.sh
    ├── kustomize_install.sh
    ├── metrics-server_install.sh
    ├── metrics-server_resource_table.py
    ├── multi_tenancy_install.sh
    ├── notebook.test.kubeflow-user-example.com.yaml
    ├── oauth2-proxy_install.sh
    ├── oauth2_dex_credentials.sh
    ├── pipeline_run_and_wait_kubeflow.py
    ├── pipeline_test.py
    ├── pipeline_v1_test.py
    ├── pipeline_v2_test.py
    ├── pipelines_install.sh
    ├── pipelines_swfs_install.sh
    ├── poddefaults.access-ml-pipeline.kubeflow-user-example-com.yaml
    ├── port_forward_gateway.sh
    ├── runasnonroot.sh
    ├── s3_helper_test.py
    ├── spark_install.sh
    ├── spark_test.sh
    ├── swfs_namespace_isolation_test.sh
    ├── training_operator_install.sh
    ├── training_operator_job.yaml
    ├── training_operator_test.sh
    ├── trivy_install.sh
    ├── trivy_scan.py
    ├── volumes_web_application_install.sh
    └── volumes_web_application_test.sh
