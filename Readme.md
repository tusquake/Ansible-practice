# Ansible Fundamentals: Configuration Management with Docker, Terraform, and GCP

> **A hands-on, end-to-end record of learning Ansible from zero: first on local Docker containers, then on real Google Cloud VMs provisioned with Terraform, followed by a look at AWX (the web UI for Ansible). Every resource created was destroyed afterwards, so the lab costs almost nothing and never touches production.**

This repository documents my Ansible learning journey. It covers the **theory** (with real-world analogies), the **exact commands** I ran, the **errors I hit and how I fixed them**, how Ansible **compares with Terraform**, a guide to **AWX**, and a **DevOps interview guide** built from what I learned.

---

## Table of Contents

1. [Overview and Tech Stack](#overview-and-tech-stack)
2. [Core Theoretical Concepts](#core-theoretical-concepts)
3. [Ansible vs. Terraform](#ansible-vs-terraform)
4. [Lab 1: Local Docker Lab](#lab-1-local-docker-lab)
5. [Lab 2: Terraform plus Ansible on GCP](#lab-2-terraform-plus-ansible-on-gcp)
6. [AWX: Ansible with a Web UI](#awx-ansible-with-a-web-ui)
7. [Real-World Troubleshooting](#real-world-troubleshooting--errors-faced)
8. [Where Ansible Fits (and Where It Does Not)](#where-ansible-fits-and-where-it-does-not)
9. [DevOps Interview Guide](#devops-interview-guide)
10. [Teardown and Cost Optimization](#teardown-and-cost-optimization)
11. [Security Notes](#security-notes)

---

## Overview and Tech Stack

### What was built

1. **Lab 1 (local):** Two Alpine Linux Docker containers acting as "remote servers". Ansible, running on a Mac, connected to them over SSH, bootstrapped Python, installed Nginx, and proved idempotency.
2. **Lab 2 (cloud):** Terraform created a custom VPC, subnet, firewall rule, storage bucket, and three Debian VMs on GCP. Ansible then configured all three VMs at the same time. Everything was destroyed with a single command.
3. **AWX (local, optional):** A walkthrough for running AWX on Minikube to see how Ansible is operated at team scale.

### Why it matters

Manual server setup does not scale. Configuring one server by hand takes five minutes. Configuring 100 takes days and invites typos. Ansible turns that work into a reviewable, repeatable text file.

### Tech Stack

| Layer | Technology | Role |
|---|---|---|
| Automation | **Ansible** | Configuration management (install, configure, deploy) |
| Infrastructure as Code | **Terraform** | Creates the cloud resources Ansible later configures |
| Local targets | **Docker** (Alpine + OpenSSH image) | Safe, free practice "servers" |
| Cloud | **GCP Compute Engine** (Debian 12, `e2-micro`) | Real remote servers |
| Web UI | **AWX** on **Minikube** | Dashboard, RBAC, scheduling, credential vault |
| Shell | macOS Terminal, GCP Cloud Shell | Control nodes |

### Architecture of the cloud lab

```
   Control Node (Cloud Shell)
   ┌────────────────────────┐
   │ 1. terraform apply     │───────► GCP creates: VPC, subnet, firewall,
   │ 2. ansible-playbook    │         bucket, 3 VMs
   └───────────┬────────────┘
               │ SSH (push model, no agent)
     ┌─────────┼──────────┐
     ▼         ▼          ▼
  lab-web-1  lab-web-2  lab-web-3     <- Ansible installs and starts Nginx
```

---

## Core Theoretical Concepts

> **The one-line version:** Ansible is a tool that logs into many machines over SSH and makes them match a text file you wrote.

### The Head Chef analogy

| Kitchen | Ansible |
|---|---|
| Head Chef | **Ansible** (the control node) |
| Line cooks | **Managed nodes** (servers, containers, VMs) |
| The chef's contact book | **Inventory** |
| The recipe | **Playbook** |
| A single step in the recipe | **Task** |
| The tool used for a step (knife, oven) | **Module** |
| "Wash hands only if not already clean" | **Idempotency** |
| Waiters who only react when the soup changes | **Handlers** |
| A self-contained "Baking Bread" recipe folder | **Role** |
| Executive command center | **AWX / Ansible Automation Platform** |

### 1. Architecture and the agentless model

- **Control node:** The machine where Ansible is installed (your laptop, Cloud Shell, a CI runner). It must be Linux, macOS, or WSL.
- **Managed nodes:** The machines being configured. They need **SSH and Python**, nothing else.
- **Push model:** Ansible connects over SSH, copies a small Python script to the target, runs it, and removes it.

Older tools (Puppet, Chef) install a background **agent** on every server that periodically **pulls** its configuration. Ansible installs nothing on targets, so there are no agents to upgrade and no extra ports to open.

> **Key takeaway:** If you can SSH into a machine and it has Python, Ansible can manage it.

### 2. Inventory (the contact book)

A file listing which machines exist, how to reach them, and how they are grouped.

**Static inventory** (a hand-written list, fine for labs):

```ini
[webservers]
192.168.1.10
192.168.1.11

[databases]
192.168.1.20

[all:vars]
ansible_user=ubuntu
```

**Dynamic inventory** (the cloud way): In GCP, VMs come and go and IPs change. A plugin asks the GCP API for the current list every time you run Ansible, so the "contact book" updates itself.

```yaml
# gcp_compute.yml  (requires: ansible-galaxy collection install google.cloud)
plugin: google.cloud.gcp_compute
projects:
  - <YOUR_PROJECT_ID>
auth_kind: application
filters:
  - labels.env = lab
keyed_groups:
  - key: labels.role
    prefix: role
```

### 3. Modules and tasks

- A **task** is one instruction: "make sure Nginx is installed."
- A **module** is the tool that carries it out: `apt`, `copy`, `service`, `user`, `file`, `command`, and thousands more.

```yaml
- name: Ensure the Nginx web server is installed   # the task description
  apt:                                              # the module
    name: nginx
    state: present
```

### 4. Idempotency (the smart checklist)

You declare the **desired state**. Ansible checks the **current state** and acts only if they differ.

| Situation | Ansible reports | Meaning |
|---|---|---|
| Nginx missing | `changed` (yellow) | Ansible fixed it |
| Nginx already installed | `ok` (green) | Nothing to do |

A plain Bash script that runs `useradd john` fails the second time ("user exists"). An Ansible playbook can run 10,000 times safely. If a run fails halfway, you just run it again.

> **Key takeaway:** A healthy playbook shows `changed=0` on the second run. That is how you test idempotency.

### 5. Playbooks and YAML

A **playbook** is a YAML file made of one or more **plays**. Each play answers three questions:

1. **Who?** `hosts:` (a group from the inventory)
2. **With what permissions?** `become: true` (use sudo/root)
3. **What steps?** `tasks:`

```yaml
---
- name: Configure Webservers       # play name
  hosts: webservers                # WHO
  become: true                     # PERMISSIONS
  tasks:                           # WHAT
    - name: Install Nginx
      apt:
        name: nginx
        state: present
        update_cache: true
    - name: Ensure Nginx is running and enabled on boot
      service:
        name: nginx
        state: started
        enabled: true
```

> **Inventory vs. playbook:** `inventory.ini` is the **address book** (WHERE). `setup_gcp.yml` is the **recipe** (WHAT). The command `ansible-playbook -i inventory.ini setup_gcp.yml` means "run this recipe against those machines."

### 6. Variables and facts

**Variables** are your own placeholders, written with `{{ }}`:

```yaml
vars:
  app_port: 8080
  user_name: deploy_user
tasks:
  - name: Create the application user
    user:
      name: "{{ user_name }}"
```

**Facts** are details Ansible discovers automatically in the first step of every play, called *Gathering Facts* (OS family, IP addresses, RAM, CPU). Use them for conditional logic:

```yaml
- name: Install Apache on Debian-family systems
  apt:
    name: apache2
    state: present
  when: ansible_os_family == "Debian"
```

### 7. Handlers (action triggers)

A **handler** is a task that sleeps until another task **notifies** it, and it runs only if that task actually **changed** something.

```yaml
tasks:
  - name: Copy new Nginx configuration
    copy:
      src: ./nginx.conf
      dest: /etc/nginx/nginx.conf
    notify: Restart Nginx          # the "tap on the shoulder"

handlers:
  - name: Restart Nginx            # name must match exactly
    service:
      name: nginx
      state: restarted
```

If the config file is unchanged, the task reports `ok`, nobody is notified, and Nginx is **not** restarted. No unnecessary downtime.

### 8. Roles (organizing like a pro)

A **role** splits a large playbook into a standard folder structure so it can be reused.

```
roles/
└── webserver/
    ├── tasks/main.yml        # the steps
    ├── handlers/main.yml     # restart triggers
    ├── vars/main.yml         # variables
    ├── defaults/main.yml     # overridable default variables
    ├── templates/            # Jinja2 templates
    └── files/                # static files to copy
```

Use the same `webserver` role in `production.yml` and `staging.yml` without copy-pasting. **Ansible Galaxy** is a public hub of ready-made roles (Docker, PostgreSQL, security hardening).

---

## Ansible vs. Terraform

**The restaurant analogy:** Terraform is the **general contractor** who builds the empty building (land, walls, plumbing, electricity). Ansible is the **head chef** who walks into that building and installs the ovens, stocks the fridge, and organizes the cooks.

| | **Terraform** | **Ansible** |
|---|---|---|
| Primary job | **Provisioning** infrastructure | **Configuring** what runs inside it |
| Creates | VMs, networks, buckets, load balancers, databases | Packages, users, config files, services |
| Style | Declarative | Mostly declarative (tasks run in order) |
| Memory | Keeps a **state file** (`terraform.tfstate`) | **No state file**; inspects the live machine each run |
| Connects via | Cloud provider APIs | SSH / WinRM (and APIs for some modules) |
| Language | HCL | YAML |
| Typical output | "3 VMs exist" | "Those 3 VMs now run Nginx" |

> **Key takeaway:** The industry "dream team" is Terraform to build the servers, then hand the IPs to Ansible to configure them. Ansible *can* create cloud resources (for example the `google.cloud.gcp_compute_instance` module), but Terraform is generally the better tool for that job.

---

## Lab 1: Local Docker Lab

**Goal:** Learn the Ansible workflow for free, with no cloud involved.

**Prerequisites:** Docker Desktop and Ansible on your machine.

```bash
# macOS
brew install ansible
brew install sshpass          # lets Ansible log in with a password
ansible --version
```

### Step 1: Start two target containers

The `linuxserver/openssh-server` image is built on **Alpine Linux**. It needs password login and sudo explicitly enabled.

```bash
docker run -d --name web1 -p 2222:2222 \
  -e PASSWORD_ACCESS=true -e SUDO_ACCESS=true \
  -e USER_NAME=ansible -e USER_PASSWORD=password \
  lscr.io/linuxserver/openssh-server:latest

docker run -d --name web2 -p 2223:2222 \
  -e PASSWORD_ACCESS=true -e SUDO_ACCESS=true \
  -e USER_NAME=ansible -e USER_PASSWORD=password \
  lscr.io/linuxserver/openssh-server:latest

docker ps      # both should be "Up"
```

### Step 2: Create the inventory

```ini
[webservers]
web1 ansible_host=127.0.0.1 ansible_port=2222
web2 ansible_host=127.0.0.1 ansible_port=2223

[webservers:vars]
ansible_user=ansible
ansible_password=password
ansible_become_password=password
ansible_ssh_extra_args='-o StrictHostKeyChecking=no'
```

> Formatting matters: use `key=value` with **no spaces around `=`**.

### Step 3: Bootstrap Python (the `raw` module)

Alpine ships without Python, and Ansible needs it on the target. The `raw` module sends a plain shell command over SSH without needing Python, which is exactly what bootstrapping requires.

```bash
ansible webservers -i inventory.ini -b -m raw -a "apk add --update --no-cache python3"
```

`-b` means "become" (use sudo).

### Step 4: Test the connection

```bash
ansible webservers -i inventory.ini -m ping
```

Expect `"ping": "pong"` for both hosts.

### Step 5: The playbook (Docker-friendly version)

Containers normally have no init system, so the `service` module cannot start Nginx. This workaround runs the binary directly:

```yaml
---
- name: Configure Webservers
  hosts: webservers
  become: true
  tasks:
    - name: Install Nginx
      apk:
        name: nginx
        state: present
        update_cache: true

    - name: Ensure Nginx is running (Docker workaround)
      command: nginx
      register: command_result
      failed_when:
        - command_result.rc != 0
        - "'Address in use' not in command_result.stderr"
      changed_when: "command_result.rc == 0"
```

### Step 6: Run it, then run it again

```bash
ansible-playbook -i inventory.ini setup_web.yml
ansible-playbook -i inventory.ini setup_web.yml   # idempotency test
```

> **Honest note:** The `command: nginx` trick is a lab hack. On a real VM you use the `service` module, which is properly idempotent by design. Running raw commands and then hand-writing `changed_when` logic is a pattern to avoid in production.

---

## Lab 2: Terraform plus Ansible on GCP

**Goal:** Mirror a real workflow. Terraform builds, Ansible configures, Terraform destroys.

> **Safety rules I followed because this was a company account:**
> - Prefix **every** resource with `lab-` so nothing can collide with existing production names.
> - Use a **dedicated custom VPC** instead of the `default` network.
> - Run `terraform destroy` from the same folder when done; Terraform only deletes what it created.
> - Set `force_destroy = true` on the lab bucket so it can be deleted even if non-empty.

Replace `<YOUR_PROJECT_ID>` below with your own project.

### Step 1: Terraform blueprint (`main.tf`)

```hcl
provider "google" {
  project = "<YOUR_PROJECT_ID>"
  region  = "us-central1"
  zone    = "us-central1-a"
}

# 1. Custom VPC (lab only)
resource "google_compute_network" "lab_vpc" {
  name                    = "lab-ansible-network"
  auto_create_subnetworks = false
}

# 2. Subnet
resource "google_compute_subnetwork" "lab_subnet" {
  name          = "lab-ansible-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.lab_vpc.id
}

# 3. Firewall rule (SSH and HTTP)
resource "google_compute_firewall" "lab_firewall" {
  name    = "lab-allow-web-and-ssh"
  network = google_compute_network.lab_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lab-http-server"]
}

# 4. Storage bucket with a unique suffix
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "lab_storage" {
  name          = "lab-assets-${random_id.bucket_suffix.hex}"
  location      = "US"
  force_destroy = true
}

# 5. Three web servers
resource "google_compute_instance" "web_servers" {
  count        = 3
  name         = "lab-web-server-${count.index + 1}"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.lab_vpc.id
    subnetwork = google_compute_subnetwork.lab_subnet.id
    access_config {} # gives each VM a public IP
  }

  tags = ["lab-http-server"]
}

output "server_ips" {
  value = google_compute_instance.web_servers[*].network_interface[0].access_config[0].nat_ip
}
```

> **Note:** SSH and HTTP open to `0.0.0.0/0` is acceptable for a short-lived lab, not for production. Restrict `source_ranges` to your own IP when you can.

### Step 2: Build the infrastructure

```bash
terraform init
terraform plan        # review what will be created
terraform apply       # type 'yes'
```

You should see **8 resources** created (network, subnet, firewall, random ID, bucket, 3 VMs) and an output block with three IPs.

### Step 3: Create SSH keys for Ansible

`gcloud` generates `~/.ssh/google_compute_engine` the first time you SSH and places the public key on the VM. Ansible reuses that key.

```bash
gcloud compute ssh lab-web-server-1 --zone=us-central1-a --command="echo 'Done'"
```

(Run it once per VM if the keys are not shared project-wide.)

### Step 4: Install Ansible in Cloud Shell (if missing)

```bash
sudo apt-get update && sudo apt-get install ansible -y
```

### Step 5: Inventory with key-based auth

```ini
[webservers]
<VM_1_EXTERNAL_IP>
<VM_2_EXTERNAL_IP>
<VM_3_EXTERNAL_IP>

[webservers:vars]
ansible_user=<YOUR_CLOUD_SHELL_USERNAME>
ansible_ssh_private_key_file=~/.ssh/google_compute_engine
ansible_ssh_extra_args='-o StrictHostKeyChecking=no'
```

Pull the IPs straight from Terraform instead of copying by hand:

```bash
terraform output -json server_ips | jq -r '.[]'
```

Key-based auth is the real-world standard. Passwords in an inventory file (as in Lab 1) are fine only for a throwaway local lab.

### Step 6: Test, then configure

```bash
ansible webservers -i inventory.ini -m ping
ansible-playbook -i inventory.ini setup_gcp.yml
```

`setup_gcp.yml` is the playbook from the [Playbooks and YAML](#5-playbooks-and-yaml) section. On a real Debian VM the standard `apt` and `service` modules work with no workarounds.

Verify in a browser: `http://<VM_EXTERNAL_IP>` should show **"Welcome to nginx!"**.

### Step 7: Destroy everything

```bash
terraform destroy -auto-approve
```

Expect `Destroy complete! Resources: 8 destroyed.`

> **Key takeaway:** One tool built eight resources and one command removed all eight. Terraform's state file is what makes that safe: it knows exactly what it created and nothing else.

---

## AWX: Ansible with a Web UI

Running `ansible-playbook` in a terminal works for one engineer. A team of 50 needs answers to questions like:

- How do we stop two people running conflicting playbooks at once?
- How can a junior engineer restart a service **without** holding the SSH keys?
- How do we schedule a playbook for 2 AM every Sunday?
- Who ran what, and when?

**AWX** is the free, open-source web application that answers these. **Ansible Automation Platform (AAP)**, formerly Ansible Tower, is Red Hat's paid, supported enterprise version (roughly the Chromium vs. Chrome relationship).

| | **AWX** | **Ansible Automation Platform** |
|---|---|---|
| Cost | Free, open source | Paid subscription |
| Support | Community | 24/7 Red Hat support |
| Stability | Newest features first, can be rough | Heavily tested |
| Deployment | You run Kubernetes yourself | Packaged installers |

### How CLI concepts map to AWX objects

| What you did in the terminal | AWX equivalent |
|---|---|
| `inventory.ini` | **Inventory** (with hosts and groups) |
| `~/.ssh/google_compute_engine` key | **Credential** (stored encrypted, injected at run time) |
| `setup_gcp.yml` on your laptop | **Project** (a Git repository AWX pulls from) |
| Your Ansible installation | **Execution Environment** (a container image with Ansible and its dependencies) |
| The `ansible-playbook ...` command | **Job Template** (playbook + inventory + credential) |
| Running it | **Job** (with full logged output) |
| Cron job | **Schedule** |
| "Who may run this?" | **RBAC** (teams, roles, permissions) |
| Chaining playbooks | **Workflow** |

### Running AWX locally (Minikube + AWX Operator)

Modern AWX is deployed on **Kubernetes** with the **AWX Operator**. The simple `docker-compose` method used by very old versions no longer applies. This needs a real machine, not Cloud Shell (it wants about 4 CPUs and 8 GB RAM).

**Prerequisites:** Docker Desktop, Minikube, `kubectl`.

```bash
# 1. Start a local cluster
minikube start --cpus=4 --memory=8g --addons=ingress
```

```yaml
# 2. kustomization.yaml  (check GitHub for the latest awx-operator release tag)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=<LATEST_RELEASE_TAG>
namespace: awx
```

```bash
# 3. Install the operator
kubectl apply -k .
kubectl get pods -n awx        # wait for the operator pod to be Running
```

```yaml
# 4. awx-demo.yaml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
spec:
  service_type: nodeport
  ingress_type: none
```

```bash
# 5. Deploy AWX and watch (takes 5 to 10 minutes)
kubectl apply -f awx-demo.yaml -n awx
kubectl get pods -n awx -w

# 6. Retrieve the generated admin password
kubectl get secret awx-demo-admin-password -o jsonpath="{.data.password}" -n awx | base64 --decode; echo

# 7. Forward the UI to your machine
kubectl port-forward service/awx-demo-service -n awx 8080:80
```

Open `http://localhost:8080` and log in as `admin`.

> **Note:** Operator versions, pod names, and service names change between releases. If a command does not match, check the [AWX Operator documentation](https://github.com/ansible/awx-operator) for the current instructions.

---

## Real-World Troubleshooting / Errors Faced

Most of the learning happened here.

### Error 1: `zsh: command not found: ansible`

**Cause:** Ansible was not installed on the Mac (and later, not present in Cloud Shell).
**Fix:**

```bash
brew install ansible                              # macOS
sudo apt-get update && sudo apt-get install ansible -y   # Debian/Ubuntu/Cloud Shell
```

### Error 2: `Permission denied (publickey,keyboard-interactive)` on Docker nodes

**Cause:** The OpenSSH image accepts only SSH keys by default, and macOS needs `sshpass` for password logins.
**Fix:** Recreate the containers with `-e PASSWORD_ACCESS=true` and run `brew install sshpass`.

### Error 3: `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`

**Cause:** Recreating a container gives it a new SSH host key on the same IP and port. Your machine remembers the old fingerprint and blocks the connection, which is exactly what it should do if someone were intercepting traffic.
**Fix (safe here because they are local throwaway containers):**

```bash
ssh-keygen -R "[127.0.0.1]:2222"
ssh-keygen -R "[127.0.0.1]:2223"
```

> Never do this casually for a production host. A changed host key there is a reason to investigate.

### Error 4: `/usr/bin/python3: not found`

**Cause:** Alpine images ship without Python, and Ansible modules run as Python on the target.
**Fix:** Bootstrap with the `raw` module (which needs no Python): `apk add --update --no-cache python3`.

### Error 5: `apk ... ERROR: Unable to open log: Permission denied`

**Cause:** The `ansible` user was not root and had no sudo rights.
**Fix:** Start containers with `-e SUDO_ACCESS=true`, add `ansible_become_password` to the inventory, and run with `-b` (become).

### Error 6: `Failed to parse inventory ... Expected key=value host variable assignment, got: ansible_host`

**Cause:** Formatting problem in `inventory.ini` (stray spaces or line breaks around `=`).
**Fix:** One host per line, `key=value` pairs separated by single spaces, no spaces around `=`.

### Error 7: `the playbook: setup_web.yml could not be found`

**Cause:** The file was not created in the current directory.
**Fix:** `ls` to check, then create it with a heredoc (`cat << 'EOF' > setup_web.yml`).

### Error 8: `Could not find the requested service nginx: host`

**Cause:** The `service` module needs an init system (systemd or OpenRC). Minimal containers do not run one.
**Fix:** In the container lab, run `nginx` via the `command` module. On real VMs, `service` just works.

### Error 9: `A 'failed_when' expression evaluated to 'True'` (Nginx "Address in use")

**Cause:** On the second run, Nginx was already bound to port 80, so `nginx` exited with an error. My `failed_when` text match said `Address already in use`, but the real message was `Address in use`.
**Fix:** Match the exact message. This is a good reminder that string-matching command output is brittle; prefer purpose-built modules.

### Error 10: `bash: !': event not found`

**Cause:** In Bash, `!` triggers history expansion, even inside double quotes.
**Fix:** Avoid `!` in commands, use single quotes, or run `set +H` to disable history expansion.

### Error 11: Terraform `Inconsistent dependency lock file` (provider `random`)

**Cause:** I added a `random_id` resource, which needs the `random` provider that was never downloaded.
**Fix:**

```bash
terraform init -upgrade
```

### Error 12: Terraform "...requires stopping it ... `allow_stopping_for_update = true`"

**Cause:** I tried to move already-running VMs onto a different subnet in place. GCP will not change a started instance's network without stopping it.
**What I did instead:** Because this was a company project, I ran `terraform destroy` on the lab, then rebuilt everything under clear `lab-` names in an isolated VPC. For a case where in-place changes are acceptable, setting `allow_stopping_for_update = true` on the resource is the documented fix.

### Error 13: Git push `403` to a repository

**Cause:** The account used for the push had no write access, or the personal access token lacked the `repo` scope (or had been revoked).
**Fix:** Authenticate as the repo owner (or be added as a collaborator) with a token that has `repo` scope. See [Security Notes](#security-notes) before doing anything with tokens.

### Troubleshooting Cheat Sheet

| Symptom | Likely cause | First thing to check |
|---|---|---|
| `UNREACHABLE` | SSH, firewall, wrong user/key/port | `ssh -i <key> user@host` manually |
| `Permission denied (publickey...)` | Wrong auth method or key | Inventory vars, `PASSWORD_ACCESS`, key path |
| `module interpreter ... not found` | No Python on target | Bootstrap with `raw`, or set `ansible_python_interpreter` |
| Task fails needing root | Missing privilege escalation | `become: true`, sudo rights, become password |
| `Could not find the requested service` | No init system (container) | Use real VMs or run the binary directly |
| Inventory parse warnings | Syntax in `.ini` | `ansible-inventory -i inventory.ini --list` |
| Playbook always shows `changed` | Non-idempotent task (`command`, `shell`) | Use a proper module, or add `creates:` / `changed_when:` |

### Handy debugging commands

```bash
ansible-inventory -i inventory.ini --list          # what Ansible sees
ansible webservers -i inventory.ini -m setup       # print all facts
ansible-playbook -i inventory.ini play.yml --check --diff   # dry run with a diff
ansible-playbook -i inventory.ini play.yml -vvv    # verbose connection details
ansible-playbook play.yml --syntax-check
```

---

## Where Ansible Fits (and Where It Does Not)

| Resource type | Ansible fit | Why |
|---|---|---|
| VMs and bare-metal servers (Compute Engine, EC2, on-prem) | **Excellent** | Direct OS access: packages, users, config, services, patching |
| Network devices (Cisco, Juniper, F5, Palo Alto) | **Excellent** | Agentless, and these devices cannot run agents |
| Application deployment steps | **Good** | Pull code, drain traffic, restart, verify |
| Security and compliance enforcement | **Good** | Apply patches and baselines across a whole fleet |
| Database **internals** (users, schemas, grants) | Possible | Though dedicated migration tools (for example Flyway) are often better for schemas |
| Serverless (Cloud Run, Lambda) | **Rarely** | There is no OS to log into; Google or AWS runs it |
| Cloud infrastructure creation | Possible, but | Terraform is generally the preferred tool |

### Why serverless usually does not need Ansible

With Cloud Run you hand the platform a container image. There is no server to SSH into, no packages to install, and no OS to patch. A typical serverless pipeline is **Docker** (package) + **Terraform** (declare the service) + **CI/CD** (build and deploy).

### When someone still asks for Ansible in a serverless project

It usually means one of the following:

1. **Pipeline orchestration:** a wrapper that runs Terraform, passes its outputs onward, and triggers later steps.
2. **Third-party API configuration:** calling SaaS REST APIs (identity, payments, monitoring) after deployment, using the `uri` module.
3. **Secrets handling:** fetching secrets from a vault and pushing them to a secret manager.
4. **Developer workstation setup:** one playbook that installs Terraform, Docker, `gcloud`, and other tools on a new laptop.

If the intent is unclear, ask directly:

> "Since we already use Terraform for the serverless infrastructure and Flyway for database migrations, what is the scope for Ansible here? Are we using it to orchestrate the CI/CD pipeline steps, or for configuring external APIs and secrets after deployment?"

---

## DevOps Interview Guide

### Part A: Standard Questions

**Q1. What is Ansible and why is it used?**
> An open-source automation tool for configuration management, application deployment, and orchestration. It lets you describe the desired state of many machines in YAML and applies it over SSH, replacing slow, error-prone manual work.

**Q2. What does "agentless" mean and why does it matter?**
> No software must be installed on managed nodes. Ansible connects over SSH (or WinRM) and runs temporary modules. That means nothing to upgrade or monitor on targets, a smaller attack surface, and instant onboarding of any host with SSH and Python.

**Q3. Push model vs. pull model?**
> Ansible **pushes** configuration from a control node when you run it. Puppet and Chef agents **pull** from a master on a schedule. Push gives immediate, controlled changes. Pull gives continuous drift correction without anyone triggering it. (Ansible can approximate pull with `ansible-pull` or scheduled AWX jobs.)

**Q4. What is idempotency?**
> Running the same playbook repeatedly produces the same end state and makes changes only where needed. Modules such as `apt`, `user`, and `copy` check current state first. First run: `changed`. Second run: `ok`.

**Q5. What is the difference between a playbook, a play, a task, and a role?**

| Term | Meaning |
|---|---|
| Playbook | A YAML file containing one or more plays |
| Play | Maps a group of hosts to a list of tasks |
| Task | One call to a module |
| Role | A reusable, standardized directory bundling tasks, vars, handlers, templates |

**Q6. What are handlers?**
> Tasks that run only when notified by another task that reported `changed`, and they run once at the end of the play, even if notified many times. Typical use: restart a service only when its config changed.

**Q7. What are facts?**
> System information gathered automatically at the start of a play (`ansible_os_family`, IPs, memory). Used for conditionals and templating. Disable with `gather_facts: false` to save time when not needed.

**Q8. Static vs. dynamic inventory?**
> Static is a hand-maintained file. Dynamic is generated at run time from a source such as the GCP, AWS, or Azure API, so autoscaled hosts are always current.

**Q9. Ansible vs. Terraform?**
> Terraform provisions infrastructure and keeps a state file. Ansible configures what runs on that infrastructure and inspects live systems each run. They complement each other.

**Q10. AWX vs. Ansible Automation Platform?**
> AWX is the free upstream project. AAP is Red Hat's supported, tested, enterprise product built from it. Both add a UI, REST API, RBAC, credential vault, scheduling, and job history.

### Part B: Tricky and Edge-Case Questions

**Q: "Your playbook shows `changed` on every run. What is wrong?"**
> It almost certainly contains a non-idempotent task, usually `command` or `shell`, which always report `changed`. Fix by switching to a purpose-built module, or add `creates:`/`removes:`, or control the result with `changed_when:` and `failed_when:`. Confirm with a second run that ends in `changed=0`.

**Q: "What happens if a playbook fails halfway through?"**
> Tasks already completed stay applied. Because tasks are idempotent, you fix the cause and re-run; finished tasks report `ok` and the run continues from the point of failure. Use `--limit @playbook.retry`-style retries or `--start-at-task` for large plays, and `block/rescue` for in-play error handling.

**Q: "Why did `service` fail inside my Docker container but work on a VM?"**
> The `service` module talks to an init system (systemd, OpenRC). Containers usually run a single process and have no init system. In containers you run the process as the container entrypoint; Ansible is better suited to VMs and bare metal.

**Q: "How do you keep secrets out of playbooks and inventories?"**
> Use **Ansible Vault** to encrypt variable files or individual values, or fetch secrets at run time from a secrets manager. In AWX, store them as Credentials, which are encrypted and injected only into the job. Never commit plaintext passwords or tokens to Git.

**Q: "How do you roll out a change to 100 servers without downtime?"**
> Use `serial:` to update in batches (for example 10 at a time), `max_fail_percentage` to abort if too many fail, a load balancer drain step (`delegate_to`) before each batch, and health checks afterward.

**Q: "How do you preview a change before applying it?"**
> `ansible-playbook play.yml --check --diff` runs in dry-run mode and shows file diffs. Not every module supports check mode perfectly, so test in a lab environment first.

**Q: "Terraform just created VMs. How do you hand them to Ansible?"**
> Options: output the IPs and generate a static inventory (`terraform output -json`), use a **dynamic inventory plugin** that queries the cloud API by labels or tags, or use the Terraform inventory provider. Dynamic inventory is the most robust because it never goes stale.

**Q: "Your company is fully serverless. Do you need Ansible?"**
> Usually not for the runtime itself, since there is no OS to configure; Terraform plus CI/CD covers it. Ansible may still add value for pipeline orchestration, third-party API configuration, secrets distribution, or workstation setup.

**Q: "What is the difference between `command`, `shell`, and `raw`?"**

| Module | Needs Python on target? | Shell features (pipes, redirects)? | Notes |
|---|---|---|---|
| `command` | Yes | No | Safest; default choice for running a binary |
| `shell` | Yes | Yes | Use only when you need pipes/redirects |
| `raw` | **No** | Yes (via the remote shell) | For bootstrapping Python or managing devices without it |

**Q: "What is `become`?"**
> Ansible's privilege escalation (sudo, su, and others). `become: true` at play or task level runs tasks as root (or `become_user`). It requires the connecting user to have the right sudo permissions.

**Q: "Where do variables get their values from, and which wins?"**
> From many places: role defaults (lowest), inventory vars, play vars, facts, extra vars passed with `-e` (highest). Knowing that `-e` always overrides everything is a common interview point.

---

## Teardown and Cost Optimization

> **Do this when you finish. Forgotten VMs, IPs, and disks keep billing quietly.**

### Terraform lab (GCP)

```bash
terraform destroy -auto-approve
```

Verify nothing remains:

```bash
gcloud compute instances list
gcloud compute networks list
gcloud compute firewall-rules list --filter="name~^lab-"
gsutil ls | grep lab-
```

### Docker lab (local)

```bash
docker rm -f web1 web2
```

### AWX / Minikube (local)

```bash
minikube delete
```

### Cost tips

| Tip | Why |
|---|---|
| Use `e2-micro` | Smallest general-purpose size |
| Use a `lab-` prefix everywhere | Easy to spot and filter for cleanup |
| Run `terraform destroy` rather than clicking in the console | Terraform removes exactly what it created |
| Set a **billing budget alert** | Catches surprises early |
| Skip managed databases in short labs | Cloud SQL can take 5 to 10 minutes to create and costs more |
| Use `terraform plan` before every `apply` | Confirms exactly what will be created or destroyed |

---

## Security Notes

> **Never paste access tokens, passwords, or private keys into chats, issues, READMEs, or commits.**

- A GitHub **personal access token** shared in plain text should be treated as **compromised**. Revoke it immediately in GitHub under Settings, Developer settings, Personal access tokens, then create a new one with only the scopes needed. Better still, use SSH keys or a credential helper so tokens never appear in command history.
- Do **not** put tokens in remote URLs (`https://<token>@github.com/...`); they get stored in `.git/config` and shell history.
- Keep `terraform.tfstate`, `*.tfvars`, and private keys out of Git. Add them to `.gitignore`:

```gitignore
*.tfstate
*.tfstate.*
.terraform/
*.tfvars
inventory.ini        # if it contains IPs or credentials
*.pem
*.key
```

- In the Docker lab, `password` as a password and `StrictHostKeyChecking=no` are acceptable **only** because the containers are local and disposable. In real environments use key-based auth, Ansible Vault, and verified host keys.
- Restrict firewall `source_ranges` to known IPs whenever possible.

---

### Suggested Repository Layout

```
ansible-learning/
├── README.md
├── docker-lab/
│   ├── inventory.ini
│   └── setup_web.yml
├── gcp-lab/
│   ├── main.tf
│   ├── inventory.ini        # or gcp_compute.yml for dynamic inventory
│   └── setup_gcp.yml
├── awx/
│   ├── kustomization.yaml
│   └── awx-demo.yaml
└── .gitignore
```

### Further Reading

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible Galaxy](https://galaxy.ansible.com/)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [AWX Operator](https://github.com/ansible/awx-operator)
- [Ansible Vault Guide](https://docs.ansible.com/ansible/latest/vault_guide/index.html)

---

*Built while learning. Corrections and contributions welcome.*
