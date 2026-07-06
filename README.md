# Secure Pipeline

Author: **Wisdom Azaglo**

GitHub Actions CI pipeline that runs security scanners on push and uploads results to DefectDojo + SonarQube running on AWS EC2 (provisioned via Terraform).

```
Push code → GitHub Actions CI → Gitleaks + Bandit + Trivy + Syft + SonarQube
                                     ↓
                               EC2 (DefectDojo :8080, SonarQube :9000)
```

---

## Deploy

### 1. Provision EC2

```bash
cd terraform

# Create a tfvars file with your settings
# (terraform.tfvars is in .gitignore — won't be committed)
cat > terraform.tfvars << 'EOF'
repo_url   = "https://github.com/wazaglo/secure-pipeline.git"
public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC..."

# Database credentials (change these)
dd_db_user       = "ddojo"
dd_db_password   = "ddojo-password"
sonar_db_user    = "sonar"
sonar_db_password = "sonar-password"
EOF

terraform init
terraform apply
```

After apply, Terraform outputs:
```
defectdojo_url = http://54.123.45.67:8080
sonarqube_url  = http://54.123.45.67:9000
```

### 2. Get the DefectDojo API Key

SSH into the EC2 and read the credentials file the bootstrap created:

```bash
ssh -i /path/to/your-key.pem ubuntu@<PUBLIC_IP>
cat /opt/secure-pipeline/defectdojo-creds.txt
```

This will show:
```
DD_URL=http://54.123.45.67:8080
DD_API_KEY=<token>
DD_PRODUCT_ID=1
DD_ENGAGEMENT_ID=1
```

### 3. Set GitHub Secrets

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|--------|-------|
| `DD_URL` | `http://<EC2_PUBLIC_IP>:8080` (from terraform output) |
| `DD_API_KEY` | From `/opt/secure-pipeline/defectdojo-creds.txt` on EC2 |
| `DD_PRODUCT_ID` | `1` (from file) |
| `DD_ENGAGEMENT_ID` | `1` (from file) |
| `SONAR_HOST_URL` | `http://<EC2_PUBLIC_IP>:9000` |
| `SONAR_TOKEN` | Generate in SonarQube UI: Login → My Account → Security → Generate Tokens |

### 4. Push Code

Push to `main` — the CI pipeline runs automatically and uploads results to your EC2 DefectDojo.

---

## CI Pipeline

| Stage | Tool | What it finds |
|---|---|---|
| 1 | Gitleaks | Hardcoded secrets, API keys, passwords |
| 2 | Bandit | Python security bugs (eval, injection, unsafe calls) |
| 3 | Trivy FS | Vulnerable dependencies, misconfigurations |
| 4 | Docker Build | Builds container image |
| 5 | Trivy Image | OS-level CVEs in container layers |
| 6 | Syft SBOM | CycloneDX software bill of materials |
| 7 | SonarQube | Code quality bugs, security hotspots |
| 8 | DefectDojo | Aggregates all findings in one dashboard |

### What each tool does

**Bandit** — Python security linter (SAST). Scans source code for security bugs: SQL injection, unsafe `eval()`/`exec()`, hardcoded passwords, insecure file permissions. Think of it as `flake8` but for security instead of style. CI generates `reports/bandit-report.json` which goes to both DefectDojo and SonarQube.

**Gitleaks** — Scans git history and files for hardcoded secrets before they reach the repo. Configured via `.gitleaks.toml`.

**Trivy** — Three-in-one scanner: filesystem (vulns in `requirements.txt`), secrets (exposed keys), and container images (OS-level CVEs in Docker layers).

**Syft** — Generates a CycloneDX Software Bill of Materials (SBOM) — complete inventory of every package. Essential for supply chain security.

**SonarQube** — Uses `sonar-project.properties` to know what to scan:
- `sonar.projectKey=employee-api` → unique project ID
- `sonar.sources=app/` → which directory to scan
- `sonar.python.bandit.reportPaths=reports/bandit-report.json` → imports Bandit findings into SonarQube's security tab
- `sonar.python.coverage.reportPaths=coverage.xml` → test coverage data
- `sonar.exclusions=**/tests/**,**/__pycache__/**,**/.env*` → files to ignore

**DefectDojo** — Aggregates results from all scanners into one dashboard. Instead of 5 separate reports, you see everything in one place.

All reports are also saved as GitHub Actions artifacts.

---

## Files

| File | Role |
|------|------|
| `terraform/` | Provisions EC2 with DefectDojo + SonarQube |
| `.github/workflows/ci-security.yml` | CI pipeline — runs on push |
| `.github/workflows/cd-deploy.yml` | Optional deploy to target |
| `app/` | Flask API — the scan target |
| `docker-compose.yml` | DefectDojo + SonarQube stack (used on EC2) |
| `.trivy.yaml` | Trivy scanner configuration |
| `.gitleaks.toml` | Gitleaks custom rules |
| `sonar-project.properties` | SonarQube scanner configuration |

---

## Destroy

```bash
cd terraform
terraform destroy
```
