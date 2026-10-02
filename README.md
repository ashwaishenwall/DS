# Fynd — Agentic DevSecOps Engineer SDE-2 Practical Assignment (AWS)

## 1. Objective

Build a low-cost, Terraform-driven DevSecOps lab on AWS with:

- OWASP Juice Shop on K3s
- ModSecurity + OWASP CRS WAF
- Wazuh Server + Indexer + Dashboard on a separate EC2
- Automated Wazuh agent enrollment and log collection
- Persistent Wazuh Indexer storage on encrypted EBS
- WireGuard private access
- Direct-origin protection
- Python readiness/log-delivery verifier using the Wazuh Indexer API
- GitHub Actions checks with Terraform validation, tests, Trivy and Gitleaks

## 2. Architecture

```text
Laptop
  |
  | WireGuard
  v
AWS App EC2
  |-- K3s
  |    `-- Juice Shop (ClusterIP, not internet-open)
  |
  `-- ModSecurity/OWASP CRS WAF (:8080)
          |
          `--> Juice Shop :3000

AWS Wazuh EC2
  |-- Wazuh Server
  |-- Wazuh Indexer :9200 (private)
  |-- Wazuh Dashboard :443 (VPN only)
  `-- encrypted 50 GiB EBS

Juice Shop/WAF logs -> Wazuh Agent -> Wazuh Server -> Indexer
                                             ^
                                             |
                                      verifier.py
```

## 3. Prerequisites

- AWS account/credits
- Existing EC2 key pair
- Terraform >= 1.6
- AWS CLI credentials
- Python 3
- WireGuard client
- Git

The assignment allows any one cloud; this implementation uses AWS only.

## 4. Configure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Set:

```hcl
aws_region          = "us-east-1"
ssh_key_name        = "YOUR_EC2_KEYPAIR"
admin_cidr          = "YOUR.PUBLIC.IP/32"
app_instance_type   = "t3.medium"
wazuh_instance_type = "t3.medium"
```

Never commit `terraform.tfvars`, credentials, private keys or state.

## 5. Deploy

The submission provides one documented command that runs Terraform and then executes the automated readiness + Wazuh Indexer log-delivery verifier:

```bash
./deploy.sh /path/to/existing-ec2-key.pem
```

Terraform itself remains the infrastructure engine. No manual EC2, Wazuh, K3s, WAF or agent enrollment steps are performed.

For a lower-level Terraform-only run:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

Terraform creates the VPC, security groups, EC2 instances and encrypted persistent Wazuh EBS volume. EC2 user-data completes the software installation.

## 6. Wait for bootstrap

```bash
terraform -chdir=terraform output
```

SSH is restricted to `admin_cidr`.

Check App:

```bash
ssh -i key.pem ubuntu@$(terraform -chdir=terraform output -raw app_public_ip)
sudo kubectl get pods -n juice-shop
docker ps
```

Check Wazuh:

```bash
ssh -i key.pem ubuntu@$(terraform -chdir=terraform output -raw wazuh_public_ip)
sudo /opt/fynd-devsecops/healthcheck.sh
```

## 7. VPN

Generate the client profile:

```bash
./scripts/vpn-client.sh \
  "$(terraform -chdir=terraform output -raw app_public_ip)" \
  /path/to/key.pem
```

Import:

```text
~/.fynd-devsecops/fynd.conf
```

into WireGuard.

Wazuh Dashboard should then be reachable using the Wazuh private IP:

```text
https://<WAZUH_PRIVATE_IP>/
```

## 8. WAF tests

Allowed request:

```bash
curl -i "http://<APP_PUBLIC_IP>:8080/"
```

Expected: HTTP 200/3xx from Juice Shop.

Deterministic blocked request:

```bash
curl -i "http://<APP_PUBLIC_IP>:8080/?id=1%20OR%201%3D1"
```

Expected:

```text
HTTP/1.1 403
```

Direct-origin bypass:

```bash
curl -i "http://<APP_PUBLIC_IP>:3000/"
```

Expected: connection blocked from outside because the Juice Shop service is ClusterIP-only and port 3000 is not exposed by the AWS security group.

## 9. Wazuh log-delivery verification

The verifier generates a fresh marker, sends it through the WAF, verifies a deterministic CRS 403 response for a SQL-injection probe, waits for Wazuh ingestion, and searches for the marker in the Wazuh Indexer API. `deploy.sh` runs this automatically and exits non-zero if any acceptance test fails.

Obtain the admin credential from the Wazuh host:

```bash
./scripts/fetch-wazuh-password.sh \
  "$(terraform -chdir=terraform output -raw wazuh_public_ip)" \
  /path/to/key.pem
```

Export the password value as:

```bash
export INDEXER_PASSWORD='...'
```

Then run:

```bash
python3 -m pip install -r verifier/requirements.txt

python3 verifier/verifier.py \
  --app-url "http://<APP_PUBLIC_IP>:8080" \
  --indexer-url "https://<WAZUH_PRIVATE_IP>:9200"
```

The verifier uses:
- readiness checks
- unique marker
- request timeout
- Indexer API search
- bounded polling
- exit 1 on failure

## 10. CI/CD

The current .github/workflows/ci.yml performs the following in the deployment workflow:

- Terraform fmt
- Terraform init with -backend=false
- Terraform validate
- Python verifier unit tests
- Python syntax compilation
- Protected AWS credential configuration
- Terraform variable generation from GitHub secrets
- Terraform apply

The repository also contains the recovery workflow under .github/workflows/recover.yml.

Important: Trivy and Gitleaks are part of the intended DevSecOps submission/checklist, but the current ci.yml in this repository does not execute those two scans. If the evaluator expects them to be enforced as CI gates, add them as separate pre-deployment jobs/steps before final submission. This README deliberately reflects the current workflow rather than claiming checks that are not executed.

AWS credentials are supplied through the protected assessment-production GitHub environment. Do not store long-lived credentials, private keys, Terraform state, or secrets in the repository.

## 11. Security

- SSH restricted to administrator CIDR
- Wazuh Dashboard only allowed through WireGuard CIDR
- Indexer is not internet-open
- Agent ports are allowed only from the application security group
- Juice Shop ClusterIP is not internet-open
- WAF is the externally exposed application endpoint
- EBS is encrypted
- Terraform state and secrets are excluded from Git
- TLS is used by the Wazuh Dashboard and Indexer with the Wazuh-generated certificates

## 12. Persistence / reruns

Wazuh Indexer data is placed on a dedicated encrypted 50 GiB EBS volume. Terraform does not define that data volume with `delete_on_termination`; the volume is therefore independent of the EC2 root disk. Re-running `terraform apply` without changing the infrastructure does not destroy Wazuh data.

For a destructive `terraform destroy`, preserve/backup the EBS volume if assessment evidence must be retained.

## 13. Cost

Target:
- App: 2 vCPU / ~4 GiB (`t3.medium`)
- Wazuh: the assignment target is approximately 4 CPU/8 GiB; the Terraform default is constrained by the current AWS organization instance-size policy.

Actual AWS cost depends on region, runtime, public IPv4, EBS, and account credits. Record the AWS Cost Explorer/credits evidence for the final submission and destroy the lab after assessment.

## 14. Verification & Evidence Checklist

Capture fresh, redacted evidence from the final tested deployment. Do not use old IP addresses or stale screenshots.

### A. Infrastructure / Terraform

    terraform -chdir=terraform output
    ./deploy.sh /path/to/existing-ec2-key.pem

Expected final output includes:

    ==========================================
    ACCEPTANCE VERIFIER PASSED
    ==========================================

### B. Application / K3s

On the application VM:

    sudo kubectl get nodes -o wide
    sudo kubectl get pods -A
    sudo kubectl -n juice-shop get svc,pods
    sudo docker ps

The K3s node and Juice Shop workload should be healthy/running.

### C. WAF — allowed request

    curl -i "http://<APP_PUBLIC_IP>:8080/"

Expected: HTTP 200/3xx from Juice Shop.

### D. WAF — deterministic block

    curl -i "http://<APP_PUBLIC_IP>:8080/?id=1%20OR%201%3D1"

Expected:

    HTTP/1.1 403

### E. Direct-origin protection

    curl -i "http://<APP_PUBLIC_IP>:3000/"

Expected: direct access is blocked/not reachable from the external path. The WAF remains the intended application ingress.

### F. WAF logs

    sudo docker ps
    sudo systemctl is-active fynd-waf-log-bridge

Review the corresponding ModSecurity/CRS event for the blocked request.

### G. WireGuard / private access

    sudo wg show
    sudo systemctl is-active wg-quick@wg0

Never expose private keys.

### H. Wazuh services

On the Wazuh VM:

    sudo systemctl is-active wazuh-manager
    sudo systemctl is-active wazuh-indexer
    sudo systemctl is-active wazuh-dashboard
    sudo /opt/fynd-devsecops/healthcheck.sh

### I. Persistent Wazuh storage

    findmnt /var/lib/wazuh-indexer
    df -hT /var/lib/wazuh-indexer

The Indexer data directory should be backed by the dedicated encrypted EBS volume.

### J. Wazuh Agent / enrollment

On the application VM:

    sudo systemctl is-active wazuh-agent
    sudo grep -E 'Connected to the server|Requesting a key' /var/ossec/logs/ossec.log | tail -10

The agent should be connected to the Wazuh Manager.

### K. Fresh Wazuh event and verifier

The normal end-to-end path is:

    ./deploy.sh /path/to/existing-ec2-key.pem

The verifier:
1. checks application readiness;
2. creates a fresh FYND_VERIFIER_MARKER UUID;
3. sends a benign marker request through the WAF;
4. requires the deterministic SQLi probe to return HTTP 403;
5. polls wazuh-alerts-* and wazuh-archives-* through the Indexer API;
6. exits 0 only when the marker is found;
7. exits 1 on timeout/failure.

For a direct verifier run:

    python3 -m pip install -r verifier/requirements.txt
    export INDEXER_PASSWORD='...'
    python3 verifier/verifier.py --app-url "http://<APP_PUBLIC_IP>:8080" --indexer-url "https://<WAZUH_PRIVATE_IP>:9200"

### L. CI/CD evidence

Capture the GitHub Actions run showing the checks actually executed by .github/workflows/ci.yml:

- Terraform fmt
- Terraform validate
- Python tests
- Python syntax compilation
- protected AWS credential configuration
- Terraform provisioning

If Trivy/Gitleaks are added before final submission, capture their successful results as well.

### M. Redaction rules

Never include:

- AWS access keys/secrets
- GitHub secrets
- Wazuh admin passwords
- WireGuard private keys
- EC2 private keys / PEM contents
- Terraform state
- tokens/cookies
- unnecessary internal identifiers

Public/private IPs should be shown only when technically useful and should be redacted for external sharing when not required.

## 15. AI use

AI was used to accelerate boilerplate generation, documentation, configuration review, and test scaffolding. All generated code was reviewed and tested as part of the assessment.

## 16. Automated bootstrap details

The EC2 user-data scripts are idempotent for normal reruns:

- App bootstrap installs Docker Compose V2, K3s, Juice Shop, ModSecurity/OWASP CRS, WireGuard and Wazuh Agent.
- The WAF uses the Juice Shop K3s ClusterIP service as its backend and exposes only port 8080.
- WAF container logs are bridged to `/opt/fynd-devsecops/waf-access.log` and collected by the Wazuh Agent with the Apache decoder.
- Wazuh Server uses the Terraform-provided private IP; no hard-coded private address is stored in the scripts.
- Wazuh Indexer data uses the dedicated encrypted EBS volume.
- Fresh Wazuh installations initialize OpenSearch Security automatically when required.
- Readiness markers are created only after service/configuration health checks pass.

## 17. Current Status / Known Gaps

The core lab implementation is in place: Terraform-managed AWS infrastructure, K3s/Juice Shop, ModSecurity/OWASP CRS, WireGuard, Wazuh Server/Indexer/Dashboard, persistent EBS, automated agent/log collection, and the Python Indexer verifier.

Before final submission, perform one fresh end-to-end run and confirm:

- deploy.sh completes successfully.
- A fresh verifier marker is visible in Wazuh Indexer.
- WAF allowed request returns 200/3xx.
- Deterministic SQLi test returns 403.
- Direct-origin access is blocked.
- WireGuard private access works.
- Wazuh Manager/Indexer/Dashboard are healthy.
- Persistent Indexer storage is mounted.
- CI checks pass.
- Trivy and Gitleaks are explicitly present as CI gates if required by the evaluator.

Do not state that there are no incomplete items until the final fresh acceptance run and evidence capture have been completed.

## 18. Teardown

```bash
./destroy.sh
```

or:

```bash
terraform -chdir=terraform destroy
```

Confirm the persistent EBS volume handling before destructive teardown if the evaluator still needs Wazuh evidence.
