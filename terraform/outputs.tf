output "public_ip" {
  description = "EC2 public IP address"
  value       = aws_eip.devsecops.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devsecops.id
}

output "defectdojo_url" {
  description = "DefectDojo dashboard URL"
  value       = "http://${aws_eip.devsecops.public_ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube dashboard URL"
  value       = "http://${aws_eip.devsecops.public_ip}:9000"
}

output "setup_instructions" {
  description = "Next steps after provisioning"
  value = <<-EOF
    ─────────────────────────────────────────────
    EC2 is ready with DefectDojo + SonarQube.

    DefectDojo: http://${aws_eip.devsecops.public_ip}:8080
    SonarQube:  http://${aws_eip.devsecops.public_ip}:9000

    SSH: ssh -i <your-key-file.pem> ubuntu@${aws_eip.devsecops.public_ip}

    ── 1. Get credentials from EC2 ──
    ssh -i <your-key-file.pem> ubuntu@${aws_eip.devsecops.public_ip}
    cat /opt/defectdojo-creds.txt

    ── 2. Set these GitHub Secrets ──
    DD_URL           = http://${aws_eip.devsecops.public_ip}:8080
    DD_API_KEY       = <from /opt/defectdojo-creds.txt>
    DD_PRODUCT_ID    = 1 (or from file)
    DD_ENGAGEMENT_ID = 1 (or from file)
    SONAR_HOST_URL   = http://${aws_eip.devsecops.public_ip}:9000
    SONAR_TOKEN      = generate in SonarQube UI: My Account → Security

    ── 3. Push code and CI will upload results automatically ──
  EOF
}
