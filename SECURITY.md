# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | ✅ |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it privately before disclosing it publicly.

**Do not** create a public GitHub issue. Instead, email: **wisdom.azaglo@example.com**

You can expect:

1. **Acknowledgment** within 48 hours of your report
2. **Regular updates** on the status of the fix
3. **Credit** for the discovery once the issue is resolved

## Scope

This project is a DevSecOps demonstration pipeline. Vulnerabilities in the scanning tools themselves (Trivy, Gitleaks, Bandit, SonarQube, DefectDojo) should be reported to their respective maintainers.

## Security Best Practices

When deploying this pipeline:

1. **Change default passwords** in `terraform.tfvars` before provisioning
2. **Restrict security group ingress** to your IP address instead of `0.0.0.0/0`
3. **Rotate the DefectDojo API key** regularly via the DefectDojo admin panel
4. **Keep the EC2 instance updated** with security patches
5. **Use HTTPS** with a reverse proxy (nginx/Caddy) for production use
