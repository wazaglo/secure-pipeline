# Troubleshooting Guide

## DefectDojo Login Fails (admin / admin123)

**Symptom:** Cannot log into DefectDojo at `http://<ip>:8080` with `admin / admin123`.

**Cause:** The `defectdojo-init` container uses `createsuperuser --noinput`, which creates the Django user but leaves the password unusable. The main `defectdojo` container's entrypoint skips creation if the user already exists, so the password is never set.

**Fix:**

```bash
cd /opt/secure-pipeline
docker compose exec defectdojo python manage.py shell -c "
from django.contrib.auth.models import User
u = User.objects.get(username='admin')
u.set_password('admin123')
u.save()
print('Password set')
"
```

## Missing `/opt/defectdojo-creds.txt`

**Symptom:** The file does not exist at either `/opt/defectdojo-creds.txt` or `/opt/secure-pipeline/defectdojo-creds.txt`.

**Cause:** The `user-data.sh` script only creates this file during cloud-init (first boot). If the DefectDojo web container wasn't healthy within the 120-second wait loop, the API call for the token fails and the file is never written.

**Fix:** Generate the credentials manually:

```bash
cd /opt/secure-pipeline

DD_API_KEY=$(curl -s -X POST "http://localhost:8080/api/v2/api-token-auth/" \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")

PRODUCT_ID=$(curl -s -X POST "http://localhost:8080/api/v2/products/" \
  -H "Authorization: Token $DD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Employee Management API", "description": "DevSecOps demo app", "prod_type": 1}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','1'))")

ENGAGEMENT_ID=$(curl -s -X POST "http://localhost:8080/api/v2/engagements/" \
  -H "Authorization: Token $DD_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"CI/CD Pipeline Scan - $(date +%Y-%m-%d)\", \"product\": $PRODUCT_ID, \"target_start\": \"$(date +%Y-%m-%d)\", \"target_end\": \"$(date -d '+30 days' +%Y-%m-%d)\", \"status\": \"In Progress\", \"engagement_type\": \"CI/CD\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','1'))")

sudo tee /opt/defectdojo-creds.txt > /dev/null << CREDSEOF
DD_URL=http://$(curl -s http://checkip.amazonaws.com):8080
DD_API_KEY=$DD_API_KEY
DD_PRODUCT_ID=$PRODUCT_ID
DD_ENGAGEMENT_ID=$ENGAGEMENT_ID
CREDSEOF
```

## DefectDojo Web Container Not Running

**Symptom:** `docker ps` shows `defectdojo-init-1`, `postgres-ddojo-1`, `redis-ddojo-1`, but **no** `defectdojo-1` container.

**Cause:** The `defectdojo` service depends on `defectdojo-init` completing successfully. If the init container failed or is still running, the web container won't start. Debug by checking logs:

```bash
docker compose -f /opt/secure-pipeline/docker-compose.yml ps
docker compose -f /opt/secure-pipeline/docker-compose.yml logs defectdojo
docker compose -f /opt/secure-pipeline/docker-compose.yml logs defectdojo-init
```

If the init container is stuck, restart the whole stack:

```bash
cd /opt/secure-pipeline
docker compose down
docker compose up -d
```

## DefectDojo Username/Password Not Working After Rerunning Init

If you run `createsuperuser` again and it says the user already exists, the password is not updated. Use the Django shell fix above.

## Docker Containers in Crash Loop

Check logs for the failing container:

```bash
docker compose -f /opt/secure-pipeline/docker-compose.yml logs <service-name>
```

Common issues:
- **Port already in use:** Another process is already bound to port 8080 or 9000.
- **Database connection refused:** PostgreSQL container isn't healthy yet; wait or check its logs.

## SonarQube Default Credentials

Login at `http://<ip>:9000` with `admin / admin`. You will be prompted to change the password on first login.

## Trivy Action Version Not Found in CI Pipeline

**Symptom:** GitHub Actions log shows:
```
Error: Unable to resolve action `aquasecurity/trivy-action@0.19.0`, unable to find version `0.19.0`
```

**Cause:** The version `0.19.0` does not exist as a git tag in `aquasecurity/trivy-action`. All tags use a `v` prefix (e.g., `v0.36.0`).

**Fix:** Update the version tag to include the `v` prefix and use a valid release:

```yaml
- uses: aquasecurity/trivy-action@v0.36.0
```

Note: The `***` in error output like `0.***9.0` is GitHub's secret masking, not the actual version string.

## SonarQube Scan Fails: Project Not Found or Unauthorized

**Symptom:** Pipeline log shows:
```
ERROR: You're not authorized to analyze this project or the project doesn't exist on SonarQube and you're not authorized to create it.
```

**Cause:** The SonarQube project `employee-api` either doesn't exist or the `SONAR_TOKEN` is missing/invalid.

**Fix:**

1. Create the project in SonarQube via API or web UI:
   ```bash
   curl -s -u 'admin:admin123' -X POST 'http://localhost:9000/api/projects/create' \
     -d 'name=employee-api&project=employee-api'
   ```

2. Generate a user token:
   ```bash
   curl -s -u 'admin:admin123' -X POST 'http://localhost:9000/api/user_tokens/generate' \
     -d 'name=github-actions&type=USER_TOKEN'
   ```

3. Set the GitHub secret `SONAR_TOKEN` to the returned token value (e.g., `squ_...`).

**Note:** The SonarQube admin password may be non-default. In this deployment the password was set to `admin123`, matching the DefectDojo admin password.

## DefectDojo Upload Fails: Engagement Doesn't Exist

**Symptom:** Pipeline log shows:
```
["Engagement '***' doesn''t exist"]
```

**Cause:** The `DD_PRODUCT_ID` or `DD_ENGAGEMENT_ID` secrets point to IDs that don't exist in DefectDojo. No product or engagement was created.

**Fix:**

1. Create a product type if none exists:
   ```bash
   curl -s -X POST 'http://localhost:8080/api/v2/product_types/' \
     -H "Authorization: Token $DD_API_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"name":"default","description":"Default product type"}'
   ```

2. Create the product:
   ```bash
   curl -s -X POST 'http://localhost:8080/api/v2/products/' \
     -H "Authorization: Token $DD_API_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"name":"employee-api","description":"Employee Management API","prod_type":1}'
   ```

3. Create an engagement:
   ```bash
   curl -s -X POST 'http://localhost:8080/api/v2/engagements/' \
     -H "Authorization: Token $DD_API_KEY" \
     -H 'Content-Type: application/json' \
     -d '{"name":"CI Pipeline Scan","description":"Automated scans from CI pipeline","product":1,"target_start":"2026-07-07","target_end":"2026-12-31","status":"In Progress"}'
   ```

4. Update GitHub secrets: `DD_PRODUCT_ID=1`, `DD_ENGAGEMENT_ID=1`, `DD_API_KEY=<token>`.

## DefectDojo UI Loads Without CSS/JS (Broken Layout)

**Symptom:** The DefectDojo web interface loads as plain HTML with no styling, missing images, and non-functional buttons. Browser console shows 404 errors for `/static/...` files.

**Cause:** Django's `collectstatic` was never run (or failed due to permissions), so static files were not copied to `/app/static/`.

**Fix:**

```bash
# Create the static directory and run collectstatic
docker exec -u 0 secure-pipeline-defectdojo-1 bash -c '
  mkdir -p /app/static && python3 manage.py collectstatic --noinput
'
```

This copies ~10,000 static files (CSS, JS, images) to the correct location.

## Terraform Deployment Issues

If `terraform apply` fails or the EC2 instance is not responding:

1. Check Terraform outputs for the public IP: `terraform output`
2. SSH into the instance and inspect cloud-init logs:
   ```bash
   sudo tail -f /var/log/cloud-init-output.log
   ```
3. Verify Docker and Docker Compose are installed:
   ```bash
   docker --version
   docker compose version
   ```
4. Check if services are running:
   ```bash
   docker compose -f /opt/secure-pipeline/docker-compose.yml ps
   ```
