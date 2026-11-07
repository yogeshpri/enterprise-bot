# Enterprise Bot — DevOps / Platform Engineering Assignment

A containerized Python Flask service deployed to Kubernetes with Helm, automated through a repeatable setup script, and accompanied by a Kubernetes debugging exercise.


---

## Table of contents

- [Project overview](#project-overview)
- [Architecture](#architecture)
- [Technology stack](#technology-stack)
- [Repository structure](#repository-structure)
- [File-by-file explanation](#file-by-file-explanation)
- [Prerequisites](#prerequisites)
- [Run the application with Docker](#run-the-application-with-docker)
- [Deploy to Kubernetes with Helm](#deploy-to-kubernetes-with-helm)
- [One-command setup](#one-command-setup)
- [Verification and troubleshooting commands](#verification-and-troubleshooting-commands)
- [Helm configuration and resource sizing](#helm-configuration-and-resource-sizing)
- [Part 4 — Kubernetes debugging lab](#part-4--kubernetes-debugging-lab)
- [Design decisions](#design-decisions)
- [What was deliberately kept out of scope](#what-was-deliberately-kept-out-of-scope)
- [Production-readiness improvements](#production-readiness-improvements)

---

## Project overview

This project demonstrates a small application delivery workflow using Docker, Kubernetes, Helm, and shell automation.

The assignment is organised around these activities:

1. **Containerize an application:** implement a small HTTP service in Python using Flask and package it as a Docker image.
2. **Deploy with Helm:** create a configurable Helm chart containing a Deployment, Service, ConfigMap, and Ingress.
3. **Automate setup:** use a root-level `setup.sh` script to create or reuse a local `kind` cluster, install the NGINX Ingress Controller, build and load the image, and install or upgrade the Helm release.
4. **Debug a supplied environment:** investigate the intentionally broken Kubernetes lab and record the symptoms, root causes, fixes, and diagnostic steps.
5. **Explain engineering decisions:** document the approach, resource sizing, limitations, and possible production improvements.

The application listens on port `8080` and exposes two HTTP endpoints:

| Endpoint | Method | Purpose | Expected result |
|---|---|---|---|
| `/` | GET | Returns application name, version, and pod hostname | JSON response |
| `/healthz` | GET | Health-check endpoint for Kubernetes probes | HTTP 200 |

The `/` endpoint reads `APP_NAME` and `VERSION` from mounted configuration files when present, and otherwise falls back to environment variables. This supports runtime configuration through Kubernetes ConfigMaps.

## Architecture

```text
                         Developer / User
                                |
                                v
                         setup.sh script
                                |
             +------------------+-------------------+
             |                  |                   |
             v                  v                   v
        Docker build        kind cluster       Helm install/upgrade
             |                  |                   |
             v                  v                   v
     enterprise-bot:1.0    Kubernetes API      chart/ templates
             |                                      |
             +------------ kind image load --------+
                                                    |
                                                    v
                                             Deployment
                                             (2 replicas)
                                                    |
                                  +-----------------+----------------+
                                  |                                  |
                                  v                                  v
                              Pod 1                              Pod 2
                         Flask :8080                         Flask :8080
                                  |                                  |
                                  +-----------------+----------------+
                                                    |
                                                    v
                                               Service
                                                    |
                                                    v
                                           NGINX Ingress
                                                    |
                                                    v
                                           http://demo.local
```

### Request flow

1. A client sends an HTTP request to the Ingress host `demo.local`.
2. The NGINX Ingress Controller routes the request to the Kubernetes Service.
3. The Service forwards traffic to a ready application pod.
4. The Flask application returns JSON or a health-check response.
5. Kubernetes liveness and readiness probes call `/healthz` to monitor the container.

## Technology stack

| Technology | Role in this project |
|---|---|
| Python 3.12 | Application runtime |
| Flask | HTTP API framework |
| Docker | Application containerization |
| Kubernetes | Container orchestration |
| kind | Local Kubernetes cluster |
| kubectl | Kubernetes resource management and troubleshooting |
| Helm | Kubernetes application packaging and deployment |
| NGINX Ingress Controller | HTTP ingress routing |
| Bash | Setup automation |

---

## Repository structure

The structure below documents the application, chart, and lab files in the repository. The `lab/` handout files are retained as part of the assignment; the supplied `scenario.sh` and `cluster-state/` are environment inputs and should not be modified.

```text
enterprise-bot/
│
├── ASSIGNMENT.md
├── Enterprise Bot.pdf
├── README.md                     # This documentation (add to repository)
├── ANSWERS.md                    # Required by assignment; verify/add before submission
├── setup.sh
│
├── service/
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
│
├── chart/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── configmap.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
│
└── lab/
    ├── scenario.sh
    ├── FINDINGS.md                # Must contain your six actual findings
    ├── part4-session.log          # Required recording; verify/add before submission
    ├── cluster-state/
    │   ├── namespace.yaml
    │   └── limits.yaml
    └── broken-chart/
        ├── Chart.yaml
        └── values.yaml             # Include any additional provided templates in your actual tree
```

> **Important repository audit:** When I inspected the public GitHub repository, its visible root contained `chart/`, `lab/`, `service/`, `ASSIGNMENT.md`, `Enterprise Bot.pdf`, and `setup.sh`. The root `README.md` and `ANSWERS.md` were not present at that time. The accessible `lab/FINDINGS.md` still contained the blank six-defect template, and I could not verify a committed `lab/part4-session.log`. Add and commit the missing deliverables, and replace the findings template with your real observations before submitting. Keep the supplied `lab/scenario.sh` and `lab/cluster-state/` unchanged. The tree above is the required/target submission layout, not a claim that every listed file was already committed when inspected.

## File-by-file explanation

### Root-level files

| File | Description |
|---|---|
| `ASSIGNMENT.md` | Original Enterprise Bot take-home assignment brief. It defines the required repository layout, application behaviour, Helm requirements, setup script behaviour, debugging rules, and README expectations. |
| `Enterprise Bot.pdf` | Supporting assignment/report document included in the repository. Refer to it for the accompanying written material and evidence. |
| `README.md` | This document. Explains the architecture, project files, setup, deployment, validation, and engineering decisions. |
| `ANSWERS.md` | Written response to the assignment's Part 5 question about migrating from ingress-nginx to Kubernetes Gateway API with no downtime. Keep the response concise and based on a safe migration sequence. |
| `setup.sh` | Executable automation script. Creates or reuses the `demo` kind cluster, installs ingress-nginx, builds the application image, loads it into kind, creates the `demo` namespace, and runs `helm upgrade --install`. |

### `service/` — application source and container image

| File | Description |
|---|---|
| `service/app.py` | Flask application entry point. Implements `GET /` and `GET /healthz`. The root endpoint returns the configured app name, version, and hostname. It checks `/etc/app-config/` for mounted ConfigMap values first, then falls back to environment variables. The server listens on `0.0.0.0:8080`. |
| `service/requirements.txt` | Python dependency list. The current application pins Flask to `3.1.2`. |
| `service/Dockerfile` | Multi-stage Docker build. The builder stage creates a virtual environment and installs dependencies. The runtime stage uses the pinned `python:3.12-slim-bookworm` base image, copies the virtual environment and application, creates and uses non-root user `appuser` (UID `10001`), and exposes port `8080`. |
| `service/.dockerignore` | Excludes Python cache files, virtual environments, Git metadata, `.env`, and log files from the Docker build context. This keeps the build context smaller and avoids copying local-only or sensitive files into the image. |

### `chart/` — Helm chart

| File | Description |
|---|---|
| `chart/Chart.yaml` | Helm chart metadata: chart name `enterprise-bot`, chart version `0.1.0`, and application version `1.0`. |
| `chart/values.yaml` | Default deployment configuration, including replica count, image repository and tag, application configuration, Service settings, Ingress host, and CPU/memory requests and limits. |
| `chart/templates/configmap.yaml` | Creates a ConfigMap containing `APP_NAME` and `VERSION` from Helm values. |
| `chart/templates/deployment.yaml` | Creates the application Deployment. Uses configurable replicas and image values, reads app configuration from the ConfigMap, defines container port `8080`, configures liveness/readiness probes, and applies resource requests and limits. |
| `chart/templates/service.yaml` | Creates a Kubernetes Service that selects the application pods and maps Service port `80` to container target port `8080`. |
| `chart/templates/ingress.yaml` | Creates an Ingress when `ingress.enabled` is true. Routes requests for the configured host (default `demo.local`) to the application Service. |

### `lab/` — debugging exercise

| File or directory | Description |
|---|---|
| `lab/scenario.sh` | Supplied lab control script. Use its `up` command to deploy the lab and its `verify` command to run the assignment's checks. Preserve the supplied script. |
| `lab/cluster-state/namespace.yaml` | Supplied namespace/environment manifest. It is part of the lab's baseline cluster state and must remain unchanged. |
| `lab/cluster-state/limits.yaml` | Supplied resource-limit/environment manifest. It must remain unchanged. |
| `lab/broken-chart/Chart.yaml` | Helm metadata for the supplied broken lab chart. |
| `lab/broken-chart/values.yaml` | Values for the supplied lab chart. Correct the chart values/templates as needed to resolve the defects. |
| `lab/broken-chart/templates/` | Supplied lab chart templates. Investigate and fix the chart defects here. Preserve workloads and the supplied image repository/tag as required by the assignment. |
| `lab/FINDINGS.md` | Debugging report. For each of the six defects, record the observed symptom with actual terminal output, the root cause, the fix, and the diagnostic steps used to identify it. |
| `lab/part4-session.log` | Terminal recording created with `script -q part4-session.log` before beginning the debugging investigation. Commit the real recording as evidence. An asciinema `.cast` recording is the alternative specified by the assignment. |

---

## Prerequisites

Install the following tools on the machine where you will run the project:

- Docker Engine
- kind
- kubectl
- Helm 3
- `curl`
- Bash

Check that the tools are available:

```bash
docker --version
kind --version
kubectl version --client
helm version
```

Docker must be running and the current user must have permission to access it. The setup script also downloads and applies the ingress-nginx kind deployment manifest, so the machine needs network access during the first setup.

## Run the application with Docker

Run these commands from the repository root:

```bash
docker build -t enterprise-bot:1.0 ./service

docker run -d \
  --name enterprise-bot \
  -p 8080:8080 \
  -e APP_NAME=enterprise-bot \
  -e VERSION=1.0 \
  enterprise-bot:1.0
```

Verify the endpoints:

```bash
curl http://localhost:8080/
curl -i http://localhost:8080/healthz
```

The root endpoint returns JSON similar to:

```json
{
  "app": "enterprise-bot",
  "version": "1.0",
  "pod": "<container-hostname>"
}
```

The hostname is generated at runtime, so its value will differ between containers.

Stop and remove the container:

```bash
docker stop enterprise-bot
docker rm enterprise-bot
```

## Deploy to Kubernetes with Helm

The root-level setup script performs the full deployment. If you want to inspect or execute the stages separately, the following commands show the intended workflow.

### 1. Create or reuse the kind cluster

```bash
kind get clusters
kind create cluster --name demo
kubectl cluster-info
kubectl get nodes
```

The setup script creates the cluster with host port mappings for HTTP and HTTPS and labels the control-plane node for ingress-nginx scheduling.

### 2. Build and load the image

```bash
docker build -t enterprise-bot:1.0 ./service
kind load docker-image enterprise-bot:1.0 --name demo
```

Loading the image into kind allows Kubernetes to use the locally built image without pushing it to a remote registry.

### 3. Create the namespace and install the chart

```bash
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install demo ./chart \
  --namespace demo \
  --wait \
  --timeout 180s
```

### 4. Inspect Kubernetes resources

```bash
kubectl get all -n demo
kubectl get ingress -n demo
kubectl describe deployment demo -n demo
kubectl get pods -n demo -o wide
```

The Helm release is named `demo` and is installed in namespace `demo`.

## One-command setup

From the repository root, make the script executable and run it:

```bash
chmod +x setup.sh
./setup.sh
```

The script is designed to be repeatable. Its workflow is:

1. Check whether the `demo` kind cluster already exists; create it if it does not.
2. Export the cluster kubeconfig and wait for the node to become Ready.
3. Apply the ingress-nginx controller manifest and wait for its Deployment rollout.
4. Build `enterprise-bot:1.0` from the `service/` directory.
5. Load the image into the `demo` kind cluster.
6. Create or reuse the `demo` namespace.
7. Install or upgrade the Helm release named `demo`.
8. Print the resulting pod, Service, and Ingress status.

Run the script a second time to check idempotency:

```bash
./setup.sh
```

A successful second run should reuse the existing cluster and complete the Helm upgrade/install without failing.

## Verification and troubleshooting commands

### Check the application pods

```bash
kubectl get pods -n demo -o wide
kubectl rollout status deployment/demo -n demo
kubectl describe pods -n demo
```

### Check Service and Ingress

```bash
kubectl get svc,ingress -n demo
kubectl describe ingress demo -n demo
```

### Check application logs

```bash
kubectl logs -n demo deployment/demo
```

If the Deployment name differs from the Helm release name in a changed configuration, first identify it with `kubectl get deployments -n demo`.

### Test through the Ingress

On the machine hosting the kind cluster, test the configured host header:

```bash
curl -i -H "Host: demo.local" http://127.0.0.1/
curl -i -H "Host: demo.local" http://127.0.0.1/healthz
```

If you want to use the hostname directly, add an appropriate hosts-file entry mapping `demo.local` to the machine's reachable address. For a local cluster on the same machine, that is commonly `127.0.0.1`.

### Render the Helm chart before applying it

```bash
helm lint ./chart

helm template demo ./chart \
  --namespace demo

helm template demo ./chart \
  --namespace demo \
  --set replicaCount=3 \
  --set config.appName=enterprise-bot-test \
  --set config.version=2.0
```

The rendered manifests should reflect the overridden values. This helps confirm that the chart is configurable rather than relying on hardcoded settings.

### Verify runtime configuration

```bash
kubectl get configmap -n demo
kubectl describe configmap demo-config -n demo
```

To inspect the application response through the Ingress, use the `curl` commands above. The response should show the configured application name and version.

### Clean up

```bash
helm uninstall demo -n demo
kind delete cluster --name demo
```

Only run the cleanup commands when you no longer need the deployment or debugging environment.

---

## Helm configuration and resource sizing

The chart's current default values are:

| Setting | Default | Purpose |
|---|---:|---|
| Replicas | `2` | Runs two application pod replicas |
| Image | `enterprise-bot:1.0` | Application container image |
| ConfigMap `APP_NAME` | `enterprise-bot` | Application identifier |
| ConfigMap `VERSION` | `1.0` | Application version |
| Service type | `ClusterIP` | Internal cluster access |
| Service port | `80` | Port exposed by the Service |
| Container target port | `8080` | Flask application port |
| Ingress host | `demo.local` | Hostname used for HTTP routing |
| CPU request | `100m` | Scheduling reservation per pod |
| Memory request | `128Mi` | Memory reservation per pod |
| CPU limit | `500m` | CPU ceiling per pod |
| Memory limit | `512Mi` | Memory ceiling per pod |

### Why these resource values?

- **CPU request — `100m`:** a small baseline reservation suitable for this lightweight Flask service while allowing Kubernetes to schedule the pod on a modest local node.
- **Memory request — `128Mi`:** a reasonable starting reservation for a small Python web application and its runtime.
- **CPU limit — `500m`:** caps CPU consumption per pod to prevent this demo service from monopolising node CPU.
- **Memory limit — `512Mi`:** provides headroom above the memory request while limiting the impact of unexpected memory growth.

These are initial values for a small assignment workload, not production capacity recommendations. Production values should be based on measured CPU and memory usage under representative load.

## Part 4 — Kubernetes debugging lab

The lab simulates a small platform containing multiple workloads and dependencies. The assignment intentionally includes six independent defects. The goal is to diagnose the actual cluster behaviour and correct the supplied lab Helm chart without hiding symptoms.

From the repository root:

```bash
cd lab

# Deploy the supplied lab scenario
./scenario.sh up

# Run the assignment verification checks
./scenario.sh verify
```

Useful diagnostic commands include:

```bash
kubectl get pods -A
kubectl get deployments -A
kubectl get services -A
kubectl get jobs -A
kubectl get events -A --sort-by=.metadata.creationTimestamp

kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl describe deployment <deployment-name> -n <namespace>
kubectl get endpoints -n <namespace>
```

For the debugging record, start a terminal session before investigating:

```bash
script -q part4-session.log
```

When the investigation is complete, type `exit` to close the recording session. Save the resulting log in `lab/` and commit it.

### Lab rules to preserve

- Fix the supplied chart under `lab/broken-chart/`.
- Do not modify `lab/scenario.sh`.
- Do not modify `lab/cluster-state/`.
- Do not change the supplied image repository or tag.
- Do not delete or disable workloads to make failing checks disappear.
- Record actual observed command output in `lab/FINDINGS.md`.
- Run `./scenario.sh verify` after applying the fixes.

The diagnostic process is important: capture the symptom, identify the root cause, explain the selected fix, and show how the evidence led to the conclusion.

## Design decisions

- **Flask:** keeps the HTTP service small and easy to inspect.
- **Environment/configuration-driven values:** separates application configuration from the application source.
- **Multi-stage Docker build:** keeps build-time dependency setup separate from the runtime image.
- **Pinned base image tag:** avoids relying on a moving `latest` tag.
- **Non-root container user:** reduces privileges inside the container.
- **ConfigMap:** keeps non-sensitive application settings outside the container image.
- **Two replicas:** demonstrates basic pod-level availability and gives the Service multiple backends.
- **Readiness and liveness probes:** allow Kubernetes to determine whether a pod can receive traffic and whether it should be restarted.
- **Resource requests and limits:** make scheduling expectations and resource ceilings explicit.
- **Helm values:** make common deployment settings configurable without editing templates.
- **kind:** provides a local Kubernetes environment without requiring a cloud account.
- **Idempotent setup script:** supports repeatable deployment and automated evaluation.

## What was deliberately kept out of scope

This is a time-boxed technical assignment, not a complete production platform. The following are not part of the current implementation unless explicitly added elsewhere in the repository:

- A remote container registry and image-publishing pipeline.
- TLS certificate provisioning and production DNS management.
- External secrets management; the ConfigMap is used only for non-sensitive settings.
- Persistent storage, because the application does not currently require it.
- Horizontal Pod Autoscaler configuration and load testing.
- A full observability stack with metrics, dashboards, tracing, and alerting.
- A CI pipeline for automated build, chart validation, and vulnerability scanning.

**Risks:** without TLS, production DNS, secrets management, observability, and tested resource sizing, this setup should be treated as a local demonstration environment rather than a production deployment.

## Production-readiness improvements

For a production deployment, I would consider:

1. Publish immutable, versioned images to a private registry and use image digests.
2. Add CI checks for unit tests, Docker build, image scanning, `helm lint`, and rendered-manifest validation.
3. Add TLS, managed DNS, and an appropriately supported ingress or Gateway API implementation.
4. Use a dedicated secret-management solution for credentials and other sensitive configuration.
5. Add metrics, centralized logs, distributed tracing, dashboards, and actionable alerts.
6. Define PodDisruptionBudgets, topology spread constraints, and appropriate affinity rules.
7. Tune requests and limits using load tests and production telemetry.
8. Add network policies, least-privilege RBAC, and container security-context hardening.
9. Add automated rollback and documented backup/recovery procedures where stateful components are introduced.
10. Test the setup and upgrade path in CI, including running the setup script more than once.
