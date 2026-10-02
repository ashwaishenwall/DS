# Assignment Acceptance Mapping

| Assignment requirement | Implementation |
|---|---|
| Terraform-based automation | `terraform/` + `deploy.sh` |
| One documented command | `./deploy.sh /path/to/key.pem` |
| No manual server/Wazuh setup | EC2 user-data bootstraps K3s, WAF, WireGuard, Wazuh and agent |
| Juice Shop on Kubernetes | K3s + `k8s/juice-shop.yaml` |
| Separate Wazuh VM | `aws_instance.wazuh` |
| Wazuh server/indexer/dashboard | Wazuh 4.14.8 assisted `-a` installation |
| Agent enrollment | Wazuh agent package with manager/registration variables |
| App/ingress log collection | Wazuh agent reads WAF access log |
| Persistent Wazuh data | dedicated encrypted 50 GiB EBS mounted at `/var/lib/wazuh-indexer` |
| VPN | WireGuard on App VM |
| WAF | ModSecurity + OWASP CRS |
| Allowed request | `curl http://APP:8080/` |
| Deterministic block | CRS SQL-injection probe (`id=1 OR 1=1`) -> 403 |
| Direct-origin bypass prevention | Juice Shop is ClusterIP-only; AWS SG exposes only WAF 8080 |
| Firewall/identity restrictions | restrictive SGs; SSH limited to `admin_cidr` |
| Secrets/state protection | `.gitignore`, no credentials/state committed |
| TLS | Wazuh-generated TLS on Dashboard/Indexer |
| Verifier | `verifier/verifier.py` |
| Unique marker | UUID marker per verification |
| Indexer API | HTTPS POST to `wazuh-alerts-*/_search` |
| Timeouts/failure exits | bounded polling + `exit 1` |
| Readiness/log delivery gate | `deploy.sh` exits non-zero before success message |
| Rerun preservation | EBS independent volume; Terraform apply doesn't recreate unchanged infra |
| CI/CD | `.github/workflows/ci.yml`: checks + gated non-destructive Terraform plan; `deploy.sh`: end-to-end deployment + acceptance verifier |
| Terraform validation | fmt + validate |
| Verifier test | pytest + Python compile |
| IaC scanning | Trivy |
| Secret scanning | Gitleaks |
| Protected deployment | GitHub Environment; deploy job requires successful checks on main |
| Cost | small EC2 target + teardown |
| Final evidence | `docs/evidence/EVIDENCE-TEMPLATE.md` |
