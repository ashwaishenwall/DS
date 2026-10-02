#!/usr/bin/env bash
set -euo pipefail

# One documented command for the assessment:
#   ./deploy.sh /path/to/existing-ec2-key.pem
#
# This wrapper is intentionally thin: Terraform creates the infrastructure,
# then the script waits for automated bootstrap and runs the acceptance
# verifier. It does not perform manual server/Wazuh setup.

KEY="${1:?Usage: ./deploy.sh /path/to/key.pem}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

terraform -chdir="$ROOT/terraform" init
terraform -chdir="$ROOT/terraform" apply -auto-approve

APP_IP="$(terraform -chdir="$ROOT/terraform" output -raw app_public_ip)"
WAZUH_IP="$(terraform -chdir="$ROOT/terraform" output -raw wazuh_public_ip)"
WAZUH_PRIVATE="$(terraform -chdir="$ROOT/terraform" output -raw wazuh_private_ip)"

echo "Waiting for automated bootstrap..."
for i in $(seq 1 60); do
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -i "$KEY" "ubuntu@$APP_IP" \
      "sudo test -f /opt/fynd-devsecops/state/app-ready"; then
    break
  fi
  sleep 10
done

ssh -i "$KEY" "ubuntu@$APP_IP" "sudo test -f /opt/fynd-devsecops/state/app-ready" \
  || { echo "Application bootstrap did not complete"; exit 1; }

for i in $(seq 1 60); do
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -i "$KEY" "ubuntu@$WAZUH_IP" \
      "sudo test -f /opt/fynd-devsecops/wazuh-ready"; then
    break
  fi
  sleep 10
done

ssh -i "$KEY" "ubuntu@$WAZUH_IP" "sudo test -f /opt/fynd-devsecops/wazuh-ready" \
  || { echo "Wazuh bootstrap did not complete"; exit 1; }

echo "Fetching Wazuh verifier credential..."
CRED="$(ssh -i "$KEY" "ubuntu@$WAZUH_IP" \
  "sudo awk '/admin/{getline; print}' /opt/fynd-devsecops/admin-credentials.txt | tr -d '[:space:]'")"

if [[ -z "$CRED" ]]; then
  echo "Could not retrieve Wazuh admin credential."
  exit 1
fi

python3 -m pip install -q -r "$ROOT/verifier/requirements.txt"

# The Indexer is private. Run the verifier from the app VM itself through
# SSH, so it can reach both the WAF and private Indexer address.
scp -i "$KEY" "$ROOT/verifier/verifier.py" "ubuntu@$APP_IP:/tmp/verifier.py"
printf '%s' "$CRED" | ssh -i "$KEY" "ubuntu@$APP_IP" \
  'umask 077; cat > /tmp/fynd-indexer-password'

ssh -i "$KEY" "ubuntu@$APP_IP" \
  "python3 -m pip install -q requests && \
   export INDEXER_PASSWORD=\$(cat /tmp/fynd-indexer-password) && \
   python3 /tmp/verifier.py \
   --app-url http://127.0.0.1:8080 \
   --indexer-url https://$WAZUH_PRIVATE:9200; \
   rm -f /tmp/fynd-indexer-password /tmp/verifier.py"

echo
echo "=========================================="
echo "ACCEPTANCE VERIFIER PASSED"
echo "=========================================="
echo "App:   http://$APP_IP:8080"
echo "Wazuh: https://$WAZUH_PRIVATE (VPN)"
