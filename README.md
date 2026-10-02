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

GitHub Actions validates:

- Terraform fmt
- Terraform validate
- Python verifier test/syntax
- Gitleaks
- Trivy IaC configuration scan

Deployment runs only after the `checks` job succeeds on `main`; GitHub Actions uses the protected `assessment-production` environment for AWS credentials. The end-to-end acceptance path remains `deploy.sh`, which waits for readiness and runs the Wazuh Indexer verifier. Do not store long-lived AWS credentials in the repository.

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

## 14. Evidence checklist

Capture redacted screenshots for:

1. AWS VPC/EC2
2. `kubectl get pods -n juice-shop`
3. Juice Shop allowed request
4. WAF blocked request (403)
5. WireGuard connected
6. Wazuh Dashboard
7. Fresh Wazuh event containing the verifier marker
8. `VERIFICATION PASSED`
9. GitHub Actions checks passed
10. Direct-origin access blocked

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

## 17. Incomplete items

Update this section before submission. If all acceptance tests pass, write:

`No known incomplete items. All assignment acceptance checks were executed and evidence is included.`

## 18. Teardown

```bash
./destroy.sh
```

or:

```bash
terraform -chdir=terraform destroy
```

Confirm the persistent EBS volume handling before destructive teardown if the evaluator still needs Wazuh evidence.
