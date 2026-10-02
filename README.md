# Fynd — Agentic DevSecOps Engineer SDE-2 Practical Assignment

> **A Terraform-driven AWS DevSecOps lab implementing application deployment, WAF protection, security telemetry, private access, persistent Wazuh storage, and automated acceptance verification.**

## 1. Executive Summary

This repository implements the Fynd DevSecOps practical assignment as an automated AWS environment.

The solution is designed around a simple principle:

**Provision → Secure → Observe → Verify → Tear down**

The environment contains:

- AWS infrastructure managed with Terraform
- An application EC2 instance running K3s
- OWASP Juice Shop deployed on Kubernetes
- ModSecurity with OWASP CRS as the application WAF
- A separate Wazuh EC2 instance running Manager, Indexer and Dashboard
- Automated Wazuh agent enrollment and application/WAF log collection
- Dedicated encrypted 50 GiB EBS storage for Wazuh Indexer data
- WireGuard for private access
- Security groups preventing direct application-origin exposure
- A Python acceptance verifier using the Wazuh Indexer API
- GitHub Actions for Terraform validation, Python tests and deployment

The implementation avoids manual server configuration during normal deployment. EC2 user-data/bootstrap scripts install and configure the required components.

---

## 2. Assignment Requirement Mapping

| Assignment area | Implementation |
|---|---|
| Infrastructure as Code | Terraform under `terraform/` |
| Application | OWASP Juice Shop on K3s |
| Container orchestration | K3s / Kubernetes |
| WAF | ModSecurity + OWASP CRS |
| Security telemetry | Wazuh Agent → Manager → Indexer |
| Wazuh UI | Wazuh Dashboard |
| Persistent storage | Encrypted 50 GiB EBS |
| Private access | WireGuard |
| Direct-origin protection | Juice Shop ClusterIP + AWS security groups |
| Acceptance verification | `verifier/verifier.py` |
| Deployment automation | `deploy.sh` |
| Teardown | `destroy.sh` |
| CI/CD | `.github/workflows/ci.yml` |
| Recovery workflow | `.github/workflows/recover.yml` |
| Documentation/evidence | `docs/` |

---

## 3. Architecture

```text
                         Internet
                            |
                            | HTTP :8080
                            v
                  +---------------------+
                  |      App EC2        |
                  |                     |
                  |  ModSecurity WAF    |
                  |  + OWASP CRS        |
                  |        |            |
                  |        v            |
                  |       K3s           |
                  |        |            |
                  |   Juice Shop        |
                  |   ClusterIP         |
                  +----------+----------+
                             |
                             | WAF / application logs
                             v
                       Wazuh Agent
                             |
                             | 1514/1515
                             v
                  +---------------------+
                  |     Wazuh EC2       |
                  |                     |
                  | Wazuh Manager       |
                  | Wazuh Indexer       |
                  | Wazuh Dashboard     |
                  |                     |
                  | Encrypted 50 GiB    |
                  | EBS data volume     |
                  +----------+----------+
                             ^
                             |
                       Indexer API
                             |
                       verifier.py
                             |
                      acceptance result


                 WireGuard VPN (private)
                          |
                          v
                 Wazuh Dashboard
```

### Network security model

- The WAF is the intended external application endpoint.
- Juice Shop is exposed internally through a Kubernetes ClusterIP.
- Application port 3000 is not opened in the application security group.
- Wazuh Indexer port 9200 is private.
- Wazuh Dashboard is intended for private/VPN access.
- SSH is restricted to the configured administrator CIDR.
- Wazuh agent ports are restricted to the application security group.

---

## 4. Repository Structure

```text
.
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── recover.yml
├── docs/
│   ├── ASSIGNMENT-MAPPING.md
│   ├── TOOLS.md
│   └── evidence/
│       └── EVIDENCE-TEMPLATE.md
├── k8s/
│   └── juice-shop.yaml
├── scripts/
│   ├── app-bootstrap.sh.tftpl
│   ├── app-reconcile.sh.tftpl
│   ├── fetch-wazuh-password.sh
│   ├── render-bootstrap.py
│   ├── smoke-test.sh
│   ├── vpn-client.sh
│   └── wazuh-bootstrap.sh.tftpl
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── variables.tf
│   └── versions.tf
├── verifier/
│   ├── requirements.txt
│   ├── test_verifier.py
│   └── verifier.py
├── waf/
│   ├── nginx.conf.template
│   └── REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
├── deploy.sh
├── destroy.sh
├── Makefile
├── README.md
└── .gitignore
```

---

## 5. Prerequisites

The deployment requires:

- AWS account/credentials
- Existing EC2 key pair
- Terraform >= 1.6
- AWS CLI
- Python 3
- Git
- WireGuard client

The implementation uses AWS.

Before deployment, configure an administrator CIDR such as:

```text
YOUR.PUBLIC.IP/32
```

Do not commit:

- `terraform.tfvars`
- Terraform state
- AWS credentials
- EC2 private keys
- WireGuard private keys
- Wazuh passwords
- tokens or cookies

---

## 6. Configuration

Create the Terraform variables file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Example:

```hcl
aws_region           = "us-east-1"
ssh_key_name         = "YOUR_EC2_KEYPAIR"
admin_cidr            = "YOUR.PUBLIC.IP/32"
app_instance_type    = "t3.medium"
wazuh_instance_type  = "t3.medium"
wireguard_cidr       = "10.8.0.0/24"
```

The exact values should be adjusted for the target AWS account and environment.

---

## 7. One-Command Deployment

The intended deployment entry point is:

```bash
./deploy.sh /path/to/existing-ec2-key.pem
```

The script:

1. Initializes Terraform.
2. Applies the infrastructure.
3. Obtains the provisioned application and Wazuh endpoints.
4. Waits for application bootstrap/readiness.
5. Waits for Wazuh bootstrap/readiness.
6. Retrieves the required Wazuh credential securely over SSH.
7. Installs verifier dependencies.
8. Copies the verifier to the application host.
9. Runs the acceptance verifier from a location that can reach the private Wazuh Indexer.
10. Fails with a non-zero exit code if acceptance checks fail.

Terraform remains the infrastructure engine; the shell script is the orchestration entry point.

---

## 8. Infrastructure

Terraform provisions the core AWS resources, including:

- VPC/networking
- subnet configuration
- application EC2
- Wazuh EC2
- application security group
- Wazuh security group
- encrypted persistent EBS volume
- required network rules
- instance bootstrap/user-data

The implementation also supports using an existing network configuration where required by the target environment.

### Instance sizing

The application uses a `t3.medium` default.

The assignment target for Wazuh is approximately 4 CPU / 8 GiB, while the current Terraform default uses `t3.medium` because of the AWS organization/instance-size constraints encountered during implementation.

This is a documented cost/capacity trade-off rather than an undocumented assumption.

---

## 9. Application Platform

The application host runs:

- Docker
- K3s
- OWASP Juice Shop

Juice Shop is deployed through Kubernetes.

The application is intentionally not exposed directly on port 3000 to the internet.

The intended path is:

```text
Client
  |
  v
ModSecurity / OWASP CRS :8080
  |
  v
K3s Service
  |
  v
Juice Shop
```

The bootstrap/reconciliation logic is designed to make normal reruns safe and to wait for application readiness before marking the host ready.

---

## 10. WAF

The WAF uses:

- ModSecurity
- OWASP Core Rule Set
- Nginx configuration
- deterministic blocking behavior for the acceptance test

The WAF listens on port 8080 and forwards allowed traffic to the Juice Shop Kubernetes service.

### Allowed request

```bash
curl -i "http://<APP_PUBLIC_IP>:8080/"
```

Expected:

```text
HTTP 200/3xx
```

### Deterministic blocked request

```bash
curl -i "http://<APP_PUBLIC_IP>:8080/?id=1%20OR%201%3D1"
```

Expected:

```text
HTTP/1.1 403
```

During implementation, this test produced an HTTP 403 and the corresponding ModSecurity/CRS processing was observed in the Wazuh security telemetry.

The implementation also observed CRS-related rules including:

- 942100
- 949110

and a custom Wazuh correlation rule for the relevant application/WAF event.

---

## 11. Direct-Origin Protection

A core security requirement is preventing a client from bypassing the WAF.

The intended external path is:

```text
Internet → WAF → Juice Shop
```

not:

```text
Internet → Juice Shop
```

Test:

```bash
curl -i "http://<APP_PUBLIC_IP>:3000/"
```

Expected behavior:

- direct origin access is not externally reachable;
- port 3000 is not exposed through the AWS security group;
- Juice Shop remains behind the WAF/Kubernetes service path.

---

## 12. Wazuh Architecture

The Wazuh host runs separately from the application host.

Components:

- Wazuh Manager
- Wazuh Indexer
- Wazuh Dashboard

The application host runs the Wazuh Agent.

Log flow:

```text
Juice Shop / WAF
       |
       v
Wazuh Agent
       |
       v
Wazuh Manager
       |
       v
Wazuh Indexer
       |
       v
Wazuh Dashboard / verifier
```

The WAF log bridge writes the relevant WAF access information to a local log file which is collected by the Wazuh Agent.

---

## 13. Wazuh Persistent Storage

Wazuh Indexer data is stored on a dedicated encrypted 50 GiB EBS volume.

The data volume is separate from the EC2 root disk and is intended to preserve Indexer data across normal instance lifecycle operations.

Useful verification commands:

```bash
findmnt /var/lib/wazuh-indexer
df -hT /var/lib/wazuh-indexer
```

For destructive teardown, preserve/backup any evidence that must remain available before destroying the environment.

---

## 14. WireGuard Private Access

WireGuard provides private access to the environment.

Generate the client configuration with:

```bash
./scripts/vpn-client.sh \
  "$(terraform -chdir=terraform output -raw app_public_ip)" \
  /path/to/key.pem
```

The generated profile is placed under:

```text
~/.fynd-devsecops/fynd.conf
```

Import the profile into the WireGuard client.

The Wazuh Dashboard is intended to be accessed through the private network using the Wazuh private IP.

Never commit or share the WireGuard private key.

---

## 15. Automated Acceptance Verifier

The verifier is implemented in:

```text
verifier/verifier.py
```

It is intentionally designed as an acceptance test rather than a simple health check.

### Verification flow

```text
1. Check application readiness
        |
2. Generate unique FYND_VERIFIER_MARKER
        |
3. Send marker request through WAF
        |
4. Send deterministic SQLi probe
        |
5. Require HTTP 403
        |
6. Wait for Wazuh ingestion
        |
7. Search Wazuh Indexer API
        |
8. Find unique marker
        |
9. Return success
```

The verifier includes:

- readiness checks
- unique UUID-based marker
- HTTP request timeout
- Wazuh Indexer API search
- bounded polling
- support for Wazuh alert/archive index patterns
- explicit non-zero failure behavior

The verifier must not silently pass when log delivery fails.

### Direct verifier execution

```bash
python3 -m pip install -r verifier/requirements.txt

export INDEXER_PASSWORD='...'

python3 verifier/verifier.py \
  --app-url "http://<APP_PUBLIC_IP>:8080" \
  --indexer-url "https://<WAZUH_PRIVATE_IP>:9200"
```

---

## 16. CI/CD

The current GitHub Actions workflow is:

```text
.github/workflows/ci.yml
```

Current checks include:

- checkout
- Terraform setup
- Python dependency installation
- Terraform formatting
- Terraform initialization with backend disabled
- Terraform validation
- Python verifier tests
- Python syntax compilation
- protected AWS credential configuration
- Terraform variable generation
- Terraform deployment

The repository also contains:

```text
.github/workflows/recover.yml
```

for recovery-related automation.

### Important CI transparency

The current `ci.yml` **does not execute Trivy or Gitleaks**.

The assignment/checklist calls for security scanning, so these should be added as explicit pre-deployment CI gates if the evaluator requires them.

This README intentionally describes the workflow that is actually present instead of claiming scans that are not currently executed.

---

## 17. Security Controls

The implementation includes the following controls:

### Network controls

- SSH restricted to administrator CIDR
- Wazuh Indexer kept private
- Wazuh agent ports restricted to the application security group
- Wazuh Dashboard intended for VPN/private access
- Juice Shop origin port not exposed
- WAF is the application ingress

### Data protection

- encrypted EBS for Wazuh Indexer data
- Terraform state excluded from Git
- secrets excluded from repository
- private keys excluded from repository

### Application security

- ModSecurity
- OWASP CRS
- deterministic WAF blocking
- direct-origin protection
- Wazuh security telemetry

### Operational security

- readiness markers
- bounded verifier polling
- non-zero failure behavior
- automated bootstrap
- reconciliation for application state

---

## 18. What Was Actually Checked During Implementation

The following checks were performed during implementation and troubleshooting.

### Terraform / AWS

- Terraform formatting/initialization/validation was exercised.
- AWS infrastructure was provisioned through Terraform.
- Security-group restrictions were tested.
- Administrator CIDR handling was tested during deployment.

### K3s / Juice Shop

- K3s node readiness was checked.
- Kubernetes workloads were inspected.
- Juice Shop service/pods were checked.
- Application readiness was used by the deployment flow.

### WAF

- An allowed request was tested through port 8080.
- A SQL-injection-style request was tested.
- The deterministic blocked request returned HTTP 403.
- ModSecurity/OWASP CRS events were inspected.
- CRS rules including 942100 and 949110 were observed during testing.
- WAF logs were bridged for Wazuh collection.

### Direct-origin protection

- The application was kept behind the WAF.
- Direct port 3000 exposure was checked against the security-group/Kubernetes design.

### WireGuard

- WireGuard service/status was checked.
- Private network access was tested.
- The Wazuh Dashboard path was designed for private/VPN access.

### Wazuh

- Wazuh Manager health was checked.
- Wazuh Indexer health was checked.
- Wazuh Dashboard health was checked.
- Wazuh Agent enrollment/connectivity was checked.
- Wazuh log collection was checked.
- Indexer persistent storage was checked.
- Wazuh configuration issues encountered during implementation were repaired and service/configuration validation was performed.

### Wazuh security event

A blocked WAF request generated Wazuh security telemetry.

During testing, the event included:

- Wazuh agent/application host
- ModSecurity/CRS detection
- HTTP 403
- Wazuh alert correlation
- custom rule handling

### Unique marker

A unique verifier marker using the `FYND_VERIFIER_MARKER-` prefix was generated and used to test the end-to-end path:

```text
WAF → log collection → Wazuh Manager → Wazuh Indexer
```

### Deployment readiness

Bootstrap readiness markers and service health checks were used to prevent the verifier from running before the environment was ready.

### Important evidence rule

Historical test IP addresses are intentionally not documented as current endpoints. Final evidence should always use fresh Terraform outputs from the final deployment.

---

## 19. Verification Checklist for Final Submission

Before submitting the repository, run a fresh deployment and capture redacted evidence.

### Infrastructure

```bash
terraform -chdir=terraform output
./deploy.sh /path/to/existing-ec2-key.pem
```

### K3s

```bash
sudo kubectl get nodes -o wide
sudo kubectl get pods -A
sudo kubectl -n juice-shop get svc,pods
```

### WAF

```bash
curl -i "http://<APP_PUBLIC_IP>:8080/"
```

and:

```bash
curl -i "http://<APP_PUBLIC_IP>:8080/?id=1%20OR%201%3D1"
```

### Direct origin

```bash
curl -i "http://<APP_PUBLIC_IP>:3000/"
```

### WAF logging

```bash
sudo docker ps
sudo systemctl is-active fynd-waf-log-bridge
```

### WireGuard

```bash
sudo wg show
sudo systemctl is-active wg-quick@wg0
```

### Wazuh

```bash
sudo systemctl is-active wazuh-manager
sudo systemctl is-active wazuh-indexer
sudo systemctl is-active wazuh-dashboard
sudo /opt/fynd-devsecops/healthcheck.sh
```

### Persistent storage

```bash
findmnt /var/lib/wazuh-indexer
df -hT /var/lib/wazuh-indexer
```

### Agent

```bash
sudo systemctl is-active wazuh-agent
sudo grep -E 'Connected to the server|Requesting a key' \
  /var/ossec/logs/ossec.log | tail -10
```

### CI

Capture the GitHub Actions run showing the checks actually executed by `ci.yml`.

If Trivy/Gitleaks are added before final submission, capture their successful results as well.

---

## 20. Evidence and Redaction

Evidence should demonstrate the security controls without exposing secrets.

### Safe evidence examples

- Terraform outputs with unnecessary identifiers redacted
- K3s status
- Juice Shop service status
- WAF HTTP 200 response
- WAF HTTP 403 response
- Wazuh service status
- Wazuh Agent connection
- Indexer storage mount
- Wazuh alert/event
- verifier success
- GitHub Actions workflow result
- architecture diagram

### Never expose

- AWS access keys
- AWS secret keys
- GitHub secrets
- Wazuh admin password
- WireGuard private keys
- EC2 private keys / PEM contents
- Terraform state
- session tokens
- cookies
- unnecessary credentials

---

## 21. AI Usage

AI tools were used during the implementation for activities such as:

- boilerplate generation
- documentation drafting
- configuration review
- troubleshooting assistance
- test scaffolding
- explanation of infrastructure/security concepts

The resulting repository was reviewed and tested against the implemented environment.

The final technical decisions, deployment, troubleshooting, verification and evidence collection remain part of the implementation workflow.

---

## 22. Cost and Design Trade-offs

The design intentionally uses a small number of instances and open-source components.

Primary infrastructure components:

- one application EC2
- one Wazuh EC2
- encrypted EBS for persistent Wazuh data
- standard AWS networking
- WireGuard
- open-source WAF/security tooling

Actual cost depends on:

- AWS region
- instance runtime
- public IPv4 usage
- EBS usage
- account credits
- organization policies

The lab should be destroyed after assessment when the environment is no longer required.

---

## 23. Known Limitations / Final Gaps

The core implementation covers the main architecture:

- Terraform-managed AWS infrastructure
- K3s/Juice Shop
- ModSecurity/OWASP CRS
- Wazuh Manager/Indexer/Dashboard
- Wazuh Agent/log collection
- encrypted persistent EBS
- WireGuard
- direct-origin protection
- automated acceptance verifier
- GitHub Actions deployment/validation

Known items to address before final submission:

1. **Trivy/Gitleaks are not currently executed by `ci.yml`.**
   Add them as explicit CI gates if required by the evaluator.

2. **A fresh final acceptance run should be captured immediately before submission.**
   Do not rely only on historical screenshots.

3. **Final evidence should use current Terraform outputs.**
   Do not publish stale IP addresses.

4. **The Wazuh instance size is currently constrained by the target AWS organization policy.**
   This is documented as a capacity/cost trade-off.

These limitations are intentionally documented so the reviewer can distinguish implemented controls from planned improvements.

---

## 24. Production Hardening Opportunities

For a production deployment, the next improvements would include:

- Trivy image/IaC scanning as a CI gate
- Gitleaks secret scanning as a CI gate
- stronger IAM least-privilege policies
- centralized secret management
- private subnets/NAT architecture
- managed certificate lifecycle
- stricter egress controls
- Wazuh high availability
- backup/restore automation
- infrastructure drift detection
- centralized audit logging
- immutable evidence storage
- stronger CI deployment approvals
- dedicated production sizing based on measured Wazuh workload

These are production-hardening improvements and are not presented as already implemented in this repository.

---

## 25. Teardown

Preferred:

```bash
./destroy.sh
```

or:

```bash
terraform -chdir=terraform destroy
```

Before destructive teardown, preserve any evidence required for evaluation and verify the handling of the persistent Wazuh EBS volume.

---

## 26. Final Submission Checklist

Before sharing the repository with the evaluator:

- [ ] Repository contains no secrets.
- [ ] Repository contains no Terraform state.
- [ ] Terraform formatting passes.
- [ ] Terraform validation passes.
- [ ] Python verifier tests pass.
- [ ] Python syntax compilation passes.
- [ ] Fresh AWS deployment completes.
- [ ] K3s/Juice Shop is healthy.
- [ ] WAF allows normal traffic.
- [ ] WAF deterministically blocks the SQLi probe with 403.
- [ ] Direct origin is protected.
- [ ] Wazuh Manager is healthy.
- [ ] Wazuh Indexer is healthy.
- [ ] Wazuh Dashboard is healthy.
- [ ] Wazuh Agent is enrolled/connected.
- [ ] WAF/application logs reach Wazuh.
- [ ] Persistent EBS storage is mounted for Indexer data.
- [ ] Unique verifier marker is searchable in Wazuh Indexer.
- [ ] Verifier fails with non-zero status on acceptance failure.
- [ ] WireGuard private access works.
- [ ] CI evidence is captured.
- [ ] Trivy/Gitleaks are added as CI gates if required.
- [ ] Screenshots/evidence are redacted.
- [ ] Final README matches the actual implementation.

---

## 27. Summary

This project demonstrates an automated DevSecOps workflow rather than isolated infrastructure components:

```text
Terraform
   ↓
AWS Infrastructure
   ↓
Automated Bootstrap
   ↓
K3s + Juice Shop
   ↓
ModSecurity + OWASP CRS
   ↓
Wazuh Agent
   ↓
Wazuh Manager
   ↓
Wazuh Indexer
   ↓
Python Acceptance Verifier
   ↓
PASS / FAIL
```

The important design goal is that deployment is reproducible, security controls are testable, logs are observable, application-origin bypass is restricted, persistent security data is retained, and the final acceptance result is machine-verifiable.
