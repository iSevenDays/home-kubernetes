# ⛵ Cluster Template

Welcome to my template designed for deploying a single Kubernetes cluster. Whether you're setting up a cluster at home on bare-metal or virtual machines (VMs), this project aims to simplify the process and make Kubernetes more accessible. This template is inspired by my personal [home-ops](https://github.com/onedr0p/home-ops) repository, providing a practical starting point for anyone interested in managing their own Kubernetes environment.

At its core, this project leverages [makejinja](https://github.com/mirkolenz/makejinja), a powerful tool for rendering templates. By reading configuration files—such as [cluster.yaml](./cluster.sample.yaml) and [nodes.yaml](./nodes.sample.yaml)—Makejinja generates the necessary configurations to deploy a Kubernetes cluster with the following features:

- Easy configuration through YAML files.
- Compatibility with home setups, whether on physical hardware or VMs.
- A modular and extensible approach to cluster deployment and management.

With this approach, you'll gain a solid foundation to build and manage your Kubernetes cluster efficiently.

## ✨ Features

A Kubernetes cluster deployed with [Talos Linux](https://github.com/siderolabs/talos) and an opinionated implementation of [Flux](https://github.com/fluxcd/flux2) using [GitHub](https://github.com/) as the Git provider, [sops](https://github.com/getsops/sops) to manage secrets and [cloudflared](https://github.com/cloudflare/cloudflared) to access applications external to your local network.

- **Required:** Some knowledge of [Containers](https://opencontainers.org/), [YAML](https://noyaml.com/), [Git](https://git-scm.com/), and a **Cloudflare account** with a **domain**.
- **Included components:** [flux](https://github.com/fluxcd/flux2), [cilium](https://github.com/cilium/cilium), [cert-manager](https://github.com/cert-manager/cert-manager), [spegel](https://github.com/spegel-org/spegel), [reloader](https://github.com/stakater/Reloader), [external-dns](https://github.com/kubernetes-sigs/external-dns) and [cloudflared](https://github.com/cloudflare/cloudflared).

**Other features include:**

- Dev env managed w/ [mise](https://mise.jdx.dev/)
- Workflow automation w/ [GitHub Actions](https://github.com/features/actions)
- Dependency automation w/ [Renovate](https://www.mend.io/renovate)
- Flux `HelmRelease` and `Kustomization` diffs w/ [flux-local](https://github.com/allenporter/flux-local)

Does this sound cool to you? If so, continue to read on! 👇

## 🚀 Let's Go

There are **5 stages** outlined below for completing this project, make sure you follow the stages in order.

### Stage 1: Machine Preparation

> [!IMPORTANT]
> If you have **3 or more nodes** it is recommended to make 3 of them controller nodes for a highly available control plane. This project configures **all nodes** to be able to run workloads. **Worker nodes** are therefore **optional**.
>
> **Minimum system requirements**
>
> | Role    | Cores    | Memory        | System Disk               |
> |---------|----------|---------------|---------------------------|
> | Control/Worker | 4 | 16GB | 256GB SSD/NVMe |

1. Head over to the [Talos Linux Image Factory](https://factory.talos.dev) and follow the instructions. Be sure to only choose the **bare-minimum system extensions** as some might require additional configuration and prevent Talos from booting without it. You can always add system extensions after Talos is installed and working.

2. This will eventually lead you to download a Talos Linux ISO (or for SBCs a RAW) image. Make sure to note the **schematic ID** you will need this later on.

3. Flash the Talos ISO or RAW image to a USB drive and boot from it on your nodes.

4. Verify with `nmap` that your nodes are available on the network. (Replace `192.168.1.0/24` with the network your nodes are on.)

    ```sh
    nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep 'Discovered'
    ```

### Stage 2: Local Workstation

> [!TIP]
> It is recommended to set the visibility of your repository to `Public` so you can easily request help if you get stuck.

1. Create a new repository by clicking the green `Use this template` button at the top of this page, then clone the new repo you just created and `cd` into it. Alternatively you can us the [GitHub CLI](https://cli.github.com/) ...

    ```sh
    export REPONAME="home-ops"
    gh repo create $REPONAME --template onedr0p/cluster-template --disable-wiki --public --clone && cd $REPONAME
    ```

2. **Install** the [Mise CLI](https://mise.jdx.dev/getting-started.html#installing-mise-cli) on your workstation.

3. **Activate** Mise in your shell by following the [activation guide](https://mise.jdx.dev/getting-started.html#activate-mise).

4. Use `mise` to install the **required** CLI tools:

    ```sh
    mise trust
    pip install pipx
    mise install
    ```

   📍 _**Having trouble installing the tools?** Try unsetting the `GITHUB_TOKEN` env var and then run these commands again_

   📍 _**Having trouble compiling Python?** Try running `mise settings python.compile=0` and then run these commands again_

5. Logout of GitHub Container Registry (GHCR) as this may cause authorization problems when using the public registry:

    ```sh
    docker logout ghcr.io
    helm registry logout ghcr.io
    ```

### Stage 3: Cloudflare configuration

> [!WARNING]
> If any of the commands fail with `command not found` or `unknown command` it means `mise` is either not install or configured incorrectly.

1. Create a Cloudflare API token for use with cloudflared and external-dns by reviewing the official [documentation](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) and following the instructions below.

   - Click the blue `Use template` button for the `Edit zone DNS` template.
   - Name your token `kubernetes`
   - Under `Permissions`, click `+ Add More` and add permissions `Zone - DNS - Edit` and `Account - Cloudflare Tunnel - Read`
   - Limit the permissions to a specific account and/or zone resources and then click `Continue to Summary` and then `Create Token`.
   - **Save this token somewhere safe**, you will need it later on.

2. Create the Cloudflare Tunnel:

    ```sh
    cloudflared tunnel login
    cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes
    ```

### Stage 4: Cluster configuration

1. Generate the config files from the sample files:

    ```sh
    task init
    ```

2. Fill out `cluster.yaml` and `nodes.yaml` configuration files using the comments in those file as a guide.

3. Template out the kubernetes and talos configuration files, if any issues come up be sure to read the error and adjust your config files accordingly.

    ```sh
    task configure
    ```

4. Push your changes to git:

   📍 _**Verify** all the `./kubernetes/**/*.sops.*` files are **encrypted** with SOPS_

    ```sh
    git add -A
    git commit -m "chore: initial commit :rocket:"
    git push
    ```

> [!TIP]
> Using a **private repository**? Make sure to paste the public key from `github-deploy.key.pub` into the deploy keys section of your GitHub repository settings. This will make sure Flux has read/write access to your repository.

### Stage 5: Bootstrap Talos, Kubernetes, and Flux

> [!WARNING]
> It might take a while for the cluster to be setup (10+ minutes is normal). During which time you will see a variety of error messages like: "couldn't get current server API group list," "error: no matching resources found", etc. 'Ready' will remain "False" as no CNI is deployed yet. **This is a normal.** If this step gets interrupted, e.g. by pressing <kbd>Ctrl</kbd> + <kbd>C</kbd>, you likely will need to [reset the cluster](#-reset) before trying again

1. Install Talos:

    ```sh
    task bootstrap:talos
    ```

2. Push your changes to git:

    ```sh
    git add -A
    git commit -m "chore: add talhelper encrypted secret :lock:"
    git push
    ```

3. Install cilium, coredns, spegel, flux and sync the cluster to the repository state:

    ```sh
    task bootstrap:apps
    ```

4. Watch the rollout of your cluster happen:

    ```sh
    kubectl get pods --all-namespaces --watch
    ```

## 📣 Post installation

### ✅ Verifications

1. Check the status of Cilium:

    ```sh
    cilium status
    ```

2. Check the status of Flux and if the Flux resources are up-to-date and in a ready state:

   📍 _Run `task reconcile` to force Flux to sync your Git repository state_

    ```sh
    flux check
    flux get sources git flux-system
    flux get ks -A
    flux get hr -A
    ```

    to manually reconcile

    ```sh
    flux reconcile hr -n openhands openhands
    ```

    ```sh
    flux reconcile kustomization -n openhands openhands --with-source
    ```

3. Check TCP connectivity to both the internal and external gateways:

   📍 _`${cluster_gateway_addr}` and `${cloudflare_gateway_addr}` are only placeholders, replace them with your actual values_

    ```sh
    nmap -Pn -n -p 443 ${cluster_gateway_addr} ${cloudflare_gateway_addr} -vv
    ```

4. Check you can resolve DNS for `echo`, this should resolve to `${cluster_gateway_addr}`:

   📍 _`${cluster_dns_gateway_addr}` and `${cloudflare_domain}` are only placeholders, replace them with your actual values_

    ```sh
    dig @${cluster_dns_gateway_addr} echo.${cloudflare_domain}
    ```

5. Check the status of your wildcard `Certificate`:

    ```sh
    kubectl -n kube-system describe certificates
    ```

6. How to check helm logs

    ```sh
    helm history -n openhands openhands
    kubectl -n openhands describe helmrelease openhands
    ```

6.1. In case of issues like
    ```
26       Thu Jun 26 13:54:37 2025 failed           openhands-0.1.1 0.9.7       Rollback "openhands" failed: cannot patch "openhands" with kind Deployment: Deployment.apps "openhands" is invalid: spec.template.spec.containers[0].env[47].valueFrom: Invalid value: "": may not be specified when `value` is not empty && cannot patch "openhands-integrations" with kind Deployment: Deployment.apps "openhands-integrations" is invalid: spec.template.spec.containers[0].env[47].valueFrom: Invalid value: "": may not be specified when `value` is not empty && cannot patch "openhands-mcp" with kind Deployment: Deployment.apps "openhands-mcp" is invalid: spec.template.spec.containers[0].env[47].valueFrom: Invalid value: "": may not be specified when `value` is not empty
    ```

check values using
    ```sh
    helm -n openhands get values openhands --revision 26 | head -n 50 | cat
    helm -n openhands get manifest openhands --revision 26 | awk '/kind: Deployment/,/---/' | head -n 100 | cat
    helm -n openhands get manifest openhands --revision 26 | grep -n "name: DB_PASS" | head -n 20 | cat
    865:        - name: DB_PASS
877:        - name: DB_PASS
1091:        - name: DB_PASS
1103:        - name: DB_PASS
1317:        - name: DB_PASS
1329:        - name: DB_PASS
helm -n openhands get manifest openhands --revision 26 | sed -n '855,890p' | cat
helm -n openhands get manifest openhands --revision 26 | sed -n '870,80p' | cat
    ```

7. How to reset database in case of migration failures

    ```sh
    helm -n openhands uninstall openhands-runtime-api --no-hooks
    kubectl scale statefulset -n openhands openhands-postgresql --replicas=0
    kubectl delete pvc -n openhands data-openhands-postgresql-0
    kubectl scale statefulset -n openhands openhands-postgresql --replicas=1

    watch for Running
    kubectl get pod -n openhands -w
    openhands-postgresql-0                     0/1     ContainerCreating   0             13s
    flux reconcile hr -n openhands openhands --with-source
    ```

8. Possible issues with OCI? Check

    ```sh
    kubectl get ocirepository openhands -n flux-system -o yaml
    ```

9. How to check all values to ensure they are correct and set properly

    ```sh
    helm get values openhands -n openhands
    ```

10. How to check for litellm deployment

    ```sh
    kubectl get svc,pods,endpoints -n openhands | grep litellm
    ```

11. How to check http routes after deployment

    ```sh
    kubectl get httproute -n openhands openhands -o yaml
    kubectl get httproute -n openhands keycloak -o yaml
    ```

12. List everything Helm is still installing.

    ```sh
    kubectl get all,secret,cm,pvc -n openhands -l app.kubernetes.io/instance=openhands
    ```

13. List flux errors in Helm release notes

    ```sh
    flux logs --level=error --since=10m | grep openhands
    ```

14. Check if helm update succeeded

    ```sh
    kubectl get helmrelease -n openhands openhands -o jsonpath='{.status.conditions[?(@.type=="Ready")]}' | jq
    ```

15. To check deployed version of openhands helm

    ```sh
    kubectl get helmrelease -n openhands openhands -o yaml | grep -A 10 -B 5 "chart\|version\|image" || echo "OpenHands not deployed or kubectl not available"
    kubectl get pods -n openhands -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' | column -t
    ```

### 🌐 Public DNS

> [!TIP]
> Use the `external` gateway on `HTTPRoutes` to make applications public to the internet.

The `external-dns` application created in the `network` namespace will handle creating public DNS records. By default, `echo` and the `flux-webhook` are the only subdomains reachable from the public internet. In order to make additional applications public you must **set the correct gateway** like in the HelmRelease for `echo`.

### 🏠 Home DNS

> [!TIP]
> Use the `internal` gateway on `HTTPRoutes` to make applications private to your network. If you're having trouble with internal DNS resolution check out [this](https://github.com/onedr0p/cluster-template/discussions/719) GitHub discussion.

`k8s_gateway` will provide DNS resolution to external Kubernetes resources (i.e. points of entry to the cluster) from any device that uses your home DNS server. For this to work, your home DNS server must be configured to forward DNS queries for `${cloudflare_domain}` to `${cluster_dns_gateway_addr}` instead of the upstream DNS server(s) it normally uses. This is a form of **split DNS** (aka split-horizon DNS / conditional forwarding).

_... Nothing working? That is expected, this is DNS after all!_

### 🪝 Github Webhook

By default Flux will periodically check your git repository for changes. In-order to have Flux reconcile on `git push` you must configure Github to send `push` events to Flux.

1. Obtain the webhook path:

   📍 _Hook id and path should look like `/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123`_

    ```sh
    kubectl -n flux-system get receiver github-webhook --output=jsonpath='{.status.webhookPath}'
    ```

2. Piece together the full URL with the webhook path appended:

    ```text
    https://flux-webhook.${cloudflare_domain}/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

3. Navigate to the settings of your repository on Github, under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook URL and your token from `github-push-token.txt`, Content type: `application/json`, Events: Choose Just the push event, and save.

## 💥 Reset

> [!CAUTION]
> **Resetting** the cluster **multiple times in a short period of time** could lead to being **rate limited by DockerHub or Let's Encrypt**.

There might be a situation where you want to destroy your Kubernetes cluster. The following command will reset your nodes back to maintenance mode.

```sh
task talos:reset
```

## 🛠️ Talos and Kubernetes Maintenance

### ⚙️ Updating Talos node configuration

> [!TIP]
> Ensure you have updated `talconfig.yaml` and any patches with your updated configuration. In some cases you **not only need to apply the configuration but also upgrade talos** to apply new configuration.

```sh
# (Re)generate the Talos config
task talos:generate-config
# Apply the config to the node
task talos:apply-node IP=? MODE=?
# e.g. task talos:apply-node IP=10.10.10.10 MODE=auto
```

### ⬆️ Updating Talos and Kubernetes versions

> [!TIP]
> Ensure the `talosVersion` and `kubernetesVersion` in `talenv.yaml` are up-to-date with the version you wish to upgrade to.

```sh
# Upgrade node to a newer Talos version
task talos:upgrade-node IP=?
# e.g. task talos:upgrade-node IP=10.10.10.10
```

```sh
# Upgrade cluster to a newer Kubernetes version
task talos:upgrade-k8s
# e.g. task talos:upgrade-k8s
```

## 🤖 Renovate

[Renovate](https://www.mend.io/renovate) is a tool that automates dependency management. It is designed to scan your repository around the clock and open PRs for out-of-date dependencies it finds. Common dependencies it can discover are Helm charts, container images, GitHub Actions and more! In most cases merging a PR will cause Flux to apply the update to your cluster.

To enable Renovate, click the 'Configure' button over at their [Github app page](https://github.com/apps/renovate) and select your repository. Renovate creates a "Dependency Dashboard" as an issue in your repository, giving an overview of the status of all updates. The dashboard has interactive checkboxes that let you do things like advance scheduling or reattempt update PRs you closed without merging.

The base Renovate configuration in your repository can be viewed at [.renovaterc.json5](.renovaterc.json5). By default it is scheduled to be active with PRs every weekend, but you can [change the schedule to anything you want](https://docs.renovatebot.com/presets-schedule), or remove it if you want Renovate to open PRs immediately.

## 🐛 Debugging

Below is a general guide on trying to debug an issue with an resource or application. For example, if a workload/resource is not showing up or a pod has started but in a `CrashLoopBackOff` or `Pending` state. These steps do not include a way to fix the problem as the problem could be one of many different things.

1. Check if the Flux resources are up-to-date and in a ready state:

   📍 _Run `task reconcile` to force Flux to sync your Git repository state_

    ```sh
    flux get sources git -A
    flux get ks -A
    flux get hr -A
    ```

2. Do you see the pod of the workload you are debugging:

    ```sh
    kubectl -n <namespace> get pods -o wide
    ```

3. Check the logs of the pod if its there:

    ```sh
    kubectl -n <namespace> logs <pod-name> -f
    ```

4. If a resource exists try to describe it to see what problems it might have:

    ```sh
    kubectl -n <namespace> describe <resource> <name>
    ```

5. Check the namespace events:

    ```sh
    kubectl -n <namespace> get events --sort-by='.metadata.creationTimestamp'
    ```

Resolving problems that you have could take some tweaking of your YAML manifests in order to get things working, other times it could be a external factor like permissions on a NFS server. If you are unable to figure out your problem see the support sections below.

## 🧹 Tidy up

Once your cluster is fully configured and you no longer need to run `task configure`, it's a good idea to clean up the repository by removing the [templates](./templates) directory and any files related to the templating process. This will help eliminate unnecessary clutter from the upstream template repository and resolve any "duplicate registry" warnings from Renovate.

1. Tidy up your repository:

    ```sh
    task template:tidy
    ```

2. Push your changes to git:

    ```sh
    git add -A
    git commit -m "chore: tidy up :broom:"
    git push
    ```

## ❔ What's next

There's a lot to absorb here, especially if you're new to these tools. Take some time to familiarize yourself with the tooling and understand how all the components interconnect. Dive into the documentation of the various tools included — they are a valuable resource. This shouldn't be a production environment yet, so embrace the freedom to experiment. Move fast, break things intentionally, and challenge yourself to fix them.

Below are some optional considerations you may want to explore.

### DNS

The template uses [k8s_gateway](https://github.com/ori-edge/k8s_gateway) to provide DNS for your applications, consider exploring [external-dns](https://github.com/kubernetes-sigs/external-dns) as an alternative.

External-DNS offers broad support for various DNS providers, including but not limited to:

- [Pi-hole](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/pihole.md)
- [UniFi](https://github.com/kashalls/external-dns-unifi-webhook)
- [Adguard Home](https://github.com/muhlba91/external-dns-provider-adguard)
- [Bind](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/rfc2136.md)

This flexibility allows you to integrate seamlessly with a range of DNS solutions to suit your environment and offload DNS from your cluster to your router, or external device.

### Secrets

SOPs is an excellent tool for managing secrets in a GitOps workflow. However, it can become cumbersome when rotating secrets or maintaining a single source of truth for secret items.

For a more streamlined approach to those issues, consider [External Secrets](https://external-secrets.io/latest/). This tool allows you to move away from SOPs and leverage an external provider for managing your secrets. External Secrets supports a wide range of providers, from cloud-based solutions to self-hosted options.

### Storage

If your workloads require persistent storage with features like replication or connectivity to NFS, SMB, or iSCSI servers, there are several projects worth exploring:

- [rook-ceph](https://github.com/rook/rook)
- [longhorn](https://github.com/longhorn/longhorn)
- [openebs](https://github.com/openebs/openebs)
- [democratic-csi](https://github.com/democratic-csi/democratic-csi)
- [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)
- [csi-driver-smb](https://github.com/kubernetes-csi/csi-driver-smb)
- [synology-csi](https://github.com/SynologyOpenSource/synology-csi)

These tools offer a variety of solutions to meet your persistent storage needs, whether you're using cloud-native or self-hosted infrastructures.

### Community Repositories

Community member [@whazor](https://github.com/whazor) created [Kubesearch](https://kubesearch.dev) to allow searching Flux HelmReleases across Github and Gitlab repositories with the `kubesearch` topic.

## 🙋 Support

### Community

- Make a post in this repository's Github [Discussions](https://github.com/onedr0p/cluster-template/discussions).
- Start a thread in the `#support` or `#cluster-template` channels in the [Home Operations](https://discord.gg/home-operations) Discord server.

<details>

<summary>Click to expand the details</summary>

<br>

- **Rate**: $50/hour (no longer than 2 hours / day).
- **What's Included**: Assistance with deployment, debugging, or answering questions related to this project.
- **What to Expect**:
  1. Sessions will focus on specific questions or issues you are facing.
  2. I will provide guidance, explanations, and actionable steps to help resolve your concerns.
  3. Support is limited to this project and does not extend to unrelated tools or custom feature development.

</details>

## 🤖 OpenHands Docker Runtime Solution

This cluster includes a working deployment of [OpenHands](https://github.com/All-Hands-AI/OpenHands), an AI-powered coding assistant, with a **Docker-in-Docker (DinD) runtime solution** specifically designed for Talos Kubernetes environments.

### The Challenge

OpenHands requires Docker daemon access to create runtime containers for code execution. However, Talos Linux uses containerd instead of Docker, making standard Docker socket mounting approaches incompatible.

### Our Solution: DinD Sidecar Architecture

```
OpenHands Container → tcp://127.0.0.1:2375 → DinD Sidecar → Runtime Containers
```

**Key Components:**

- **Main OpenHands Container**: Runs the web application and AI assistant
- **DinD Sidecar Container**: Provides Docker daemon via `docker:27-dind` image
- **TCP Communication**: Secure localhost-only Docker API access
- **Dynamic Runtime Containers**: Created inside DinD for each conversation session

### Implementation Details

**PostRenderer Solution:**
The DinD sidecar is implemented using Flux HelmRelease `postRenderers` with Kustomize strategic merge patches. This approach modifies the Helm chart output to add the sidecar container and environment variables without requiring chart modifications.

**Pod Configuration:**

```yaml
# Shows 2/2 Running (OpenHands + DinD sidecar)
kubectl get pods -n openhands
openhands-66c8998c7f-cpzx6  2/2  Running
```

**Environment Variables:**

- `RUNTIME=docker` - Enables Docker runtime mode
- `DOCKER_HOST=tcp://127.0.0.1:2375` - Points to DinD sidecar
- `SANDBOX_RUNTIME_BINDING_ADDRESS=127.0.0.1` - Localhost binding for security
- `DOCKER_HOST_ADDR=127.0.0.1` - Override host.docker.internal with localhost
- `SANDBOX_LOCAL_RUNTIME_URL=http://127.0.0.1` - Local runtime URL

**Resources:**

- **DinD Sidecar**: 512Mi-2Gi memory, 250m-1000m CPU, privileged security context
- **Docker Storage**: 20Gi ephemeral volume for container images and data

### How Runtime Containers Work

When you create a conversation in OpenHands:

1. **Container Creation**: OpenHands calls Docker API → DinD creates runtime container
2. **Naming**: `openhands-runtime-{session_id}` (e.g., `openhands-runtime-d2a6463622b04fe0af52a514ff3c837a`)
3. **Networking**: Dynamic port allocation (e.g., ports 31640, 34547)
4. **Lifecycle**: Containers are ephemeral - created per session, destroyed when done

**Important**: Runtime containers exist **inside the DinD sidecar**, not as separate Kubernetes pods. They don't appear in `kubectl get pods` but can be seen with:

```bash
kubectl exec -c docker-daemon openhands-pod -- docker ps
```

### Security Considerations

- **Privileged DinD**: Required for Docker daemon functionality
- **Localhost Binding**: Docker API only accessible within the pod
- **Resource Limits**: Prevents resource exhaustion
- **Ephemeral Storage**: Runtime containers use temporary storage

### Deployment Method

The DinD sidecar is deployed using **Flux HelmRelease PostRenderers** with Kustomize strategic merge patches. This approach:

1. **Modifies Helm Output**: PostRenderers apply patches to the Helm chart output before deployment
2. **No Chart Modifications**: Works with the upstream OpenHands chart without requiring forks
3. **GitOps Compatible**: Fully declarative and managed through Flux
4. **Automatic Updates**: Patches are applied automatically during Helm upgrades

```yaml
# In HelmRelease spec:
postRenderers:
  - kustomize:
      patches:
        - target:
            kind: Deployment
            name: openhands
          patch: |
            # Strategic merge patch adds DinD sidecar and environment variables
```

This approach successfully resolves the "Failed to create agent session: ConnectError" issue that prevented OpenHands from working on Talos Kubernetes.

### Verification

**Success Indicators:**

- Pod status: `2/2 Running`
- Logs show: `Container started: openhands-runtime-{session_id}`
- Conversations can be created and execute code successfully

## 🙌 Related Projects

If this repo is too hot to handle or too cold to hold check out these following projects.

- [ajaykumar4/cluster-template](https://github.com/ajaykumar4/cluster-template) - _A template for deploying a Talos Kubernetes cluster including Argo for GitOps_
- [khuedoan/homelab](https://github.com/khuedoan/homelab) - _Fully automated homelab from empty disk to running services with a single command._
- [mitchross/k3s-argocd-starter](https://github.com/mitchross/k3s-argocd-starter) - starter kit for k3s, argocd
- [ricsanfre/pi-cluster](https://github.com/ricsanfre/pi-cluster) - _Pi Kubernetes Cluster. Homelab kubernetes cluster automated with Ansible and FluxCD_
- [techno-tim/k3s-ansible](https://github.com/techno-tim/k3s-ansible) - _The easiest way to bootstrap a self-hosted High Availability Kubernetes cluster. A fully automated HA k3s etcd install with kube-vip, MetalLB, and more. Build. Destroy. Repeat._

## ⭐ Stargazers

<div align="center">

<a href="https://star-history.com/#onedr0p/cluster-template&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=onedr0p/cluster-template&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=onedr0p/cluster-template&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=onedr0p/cluster-template&type=Date" />
  </picture>
</a>

</div>

## 🤝 Thanks

Big shout out to all the contributors, sponsors and everyone else who has helped on this project.

## ⚙️ Configuration Management

This project uses `makejinja` to template Kubernetes and Talos configurations. Centralized configuration is managed primarily in the `cluster.yaml` file. This approach allows you to define a variable once and use it across multiple configuration files.

### How to Add a New Configuration Value

1. **Define the Variable:** Open the `cluster.yaml` file and add your new configuration value. For example, if you want to add a new timeout setting, you would add a line like this:

    ```yaml
    # cluster.yaml
    # ... existing content ...
    new_timeout_value: 3600
    ```

2. **Reference the Variable:** In any template file (files ending with `.j2`), you can reference your new variable using the `#{ variable_name }#` syntax. For example, in a `helmrelease.yaml.j2` file:

    ```yaml
    # templates/config/some/app/helmrelease.yaml.j2
    apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    # ... other settings ...
    spec:
      timeout: #{ new_timeout_value }#s
      # ... other specs ...
    ```

    _Notice how you can combine the variable with other static text like the `s` for seconds._

3. **Regenerate Configurations:** After adding or modifying variables, you must run the `task configure` command to apply your changes to the output manifests.

    ```sh
    task configure
    ```

4. **Commit and Push:** Finally, commit the changes to your `cluster.yaml` and the newly generated manifests to your Git repository. Flux will then apply these changes to your cluster.

    ```sh
    git add -A
    git commit -m "feat: add and use new_timeout_value"
    git push
    ```

This process ensures that your configurations are consistent, version-controlled, and easy to manage.
