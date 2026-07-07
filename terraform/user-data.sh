#!/bin/bash
set -euo pipefail

echo "[$(date)] Starting DevSecOps EC2 bootstrap..."

apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

echo "[$(date)] Docker installed: $(docker --version)"

# Add swap for SonarQube Elasticsearch on small instances
if [ "$(free -m | awk '/^Swap:/ {print $2}')" -eq 0 ]; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "[$(date)] 1GB swap file created"
fi

PROJECT_DIR="/opt/secure-pipeline"

mkdir -p /opt
cd /opt
git clone "${repo_url}" "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "[$(date)] Repo cloned from ${repo_url}"

cat > .env << 'ENVEOF'
# ─── DefectDojo Database ───
DD_POSTGRES_DB=defectdojo
DD_POSTGRES_USER=${dd_db_user}
DD_POSTGRES_PASSWORD=${dd_db_password}

# ─── DefectDojo Django ───
DD_DATABASE_URL=postgres://${dd_db_user}:${dd_db_password}@postgres-ddojo:5432/defectdojo
DD_SECRET_KEY=${dd_secret_key}
DD_CREDENTIAL_AES_256_KEY=key1234567890123456789012345678901
DD_ADMIN_USER=admin
DD_ADMIN_PASSWORD=${dd_admin_password}
DD_ADMIN_MAIL=admin@example.com
DD_BASE_URL=http://${public_ip}:8080
DD_ALLOWED_HOSTS=localhost,defectdojo,${public_ip}
DD_EMAIL_URL=smtp://localhost:1025
DD_CELERY_BROKER_URL=redis://redis-ddojo:6379/0
DD_CELERY_RESULT_BACKEND=redis://redis-ddojo:6379/0
DD_DEBUG=False
DD_LOGIN_REDIRECT_URL=http://${public_ip}:8080/

# ─── SonarQube Database ───
SONAR_POSTGRES_DB=sonarqube
SONAR_POSTGRES_USER=${sonar_db_user}
SONAR_POSTGRES_PASSWORD=${sonar_db_password}
SONAR_JDBC_URL=jdbc:postgresql://postgres-sonar:5432/sonarqube

# ─── SonarQube ───
SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
SONAR_SEARCH_JAVAOPTS=-Xms256m -Xmx256m
ENVEOF

echo "[$(date)] .env file created"

docker compose pull
docker compose up -d

echo "[$(date)] Services started."

for i in $(seq 1 12); do
  sleep 10
  dd_ok=false
  sq_ok=false
  curl -sf http://localhost:8080/api/v2/ > /dev/null 2>&1 && dd_ok=true
  curl -sf http://localhost:9000/ > /dev/null 2>&1 && sq_ok=true
  if $dd_ok && $sq_ok; then
    echo "[$(date)] Both services healthy."
    break
  fi
  echo "[$(date)] Waiting... ($${i}/12)"
done

echo "[$(date)] Checking final status:"
curl -sf http://localhost:8080/api/v2/ && echo "  DefectDojo: OK" || echo "  DefectDojo: FAIL"
curl -sf http://localhost:9000/ && echo "  SonarQube: OK" || echo "  SonarQube: FAIL"

# ─────────────────────────────────────────────
# DefectDojo Init: Create product + engagement
# ─────────────────────────────────────────────
echo "[$(date)] Initializing DefectDojo..."

DD_API_KEY=$(curl -s -X POST "http://localhost:8080/api/v2/api-token-auth/" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"admin\", \"password\": \"${dd_admin_password}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

if [ -z "$DD_API_KEY" ]; then
  echo "[!] Failed to get DefectDojo API key"
else
  echo "[+] API key obtained"

  PRODUCT_ID=$(curl -s -X POST "http://localhost:8080/api/v2/products/" \
    -H "Authorization: Token $DD_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"name": "Employee Management API", "description": "DevSecOps demo app", "prod_type": 1}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

  if [ -z "$PRODUCT_ID" ]; then
    PRODUCT_ID=$(curl -s "http://localhost:8080/api/v2/products/?name=Employee%20Management%20API" \
      -H "Authorization: Token $DD_API_KEY" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][0]['id'] if d['count']>0 else '')" 2>/dev/null || echo "1")
  fi
  echo "[+] Product ID: $PRODUCT_ID"

  ENGAGEMENT_ID=$(curl -s -X POST "http://localhost:8080/api/v2/engagements/" \
    -H "Authorization: Token $DD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"CI/CD Pipeline Scan - $(date +%Y-%m-%d)\", \"product\": $PRODUCT_ID, \"target_start\": \"$(date +%Y-%m-%d)\", \"target_end\": \"$(date -d '+30 days' +%Y-%m-%d)\", \"status\": \"In Progress\", \"engagement_type\": \"CI/CD\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

  if [ -z "$ENGAGEMENT_ID" ]; then
    ENGAGEMENT_ID=$(curl -s "http://localhost:8080/api/v2/engagements/?product=$PRODUCT_ID&name=CI%2FCD%20Pipeline%20Scan%20-%20$(date +%Y-%m-%d)" \
      -H "Authorization: Token $DD_API_KEY" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['results'][0]['id'] if d['count']>0 else '')" 2>/dev/null || echo "1")
  fi
  echo "[+] Engagement ID: $ENGAGEMENT_ID"

  # Save credentials for CI use
  cat > /opt/defectdojo-creds.txt << CREDSEOF
DD_URL=http://${public_ip}:8080
DD_API_KEY=$DD_API_KEY
DD_PRODUCT_ID=$PRODUCT_ID
DD_ENGAGEMENT_ID=$ENGAGEMENT_ID
CREDSEOF
  echo "[+] Credentials saved to /opt/defectdojo-creds.txt"
fi

echo ""
echo "[$(date)] Bootstrap complete."
echo "DefectDojo: http://${public_ip}:8080  (admin / ${dd_admin_password})"
echo "SonarQube:  http://${public_ip}:9000  (admin / admin)"
echo ""
echo "CI credentials: cat /opt/defectdojo-creds.txt"
