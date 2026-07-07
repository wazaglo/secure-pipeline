variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "public_key" {
  description = "SSH public key content for EC2 access"
  type        = string
}

variable "project_name" {
  description = "Project name for resource tagging"
  default     = "secure-pipeline"
}

variable "repo_url" {
  description = "URL of the GitHub repo"
  type        = string
}

variable "dd_admin_password" {
  description = "DefectDojo admin password"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "dd_secret_key" {
  description = "DefectDojo Django secret key"
  type        = string
  sensitive   = true
  default     = "defectdojo-secret-key-change-in-prod-12345"
}

variable "sonar_admin_password" {
  description = "SonarQube admin password"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "dd_db_user" {
  description = "DefectDojo PostgreSQL user"
  type        = string
  default     = "ddojo"
}

variable "dd_db_password" {
  description = "DefectDojo PostgreSQL password"
  type        = string
  sensitive   = true
  default     = "ddojo-password"
}

variable "sonar_db_user" {
  description = "SonarQube PostgreSQL user"
  type        = string
  default     = "sonar"
}

variable "sonar_db_password" {
  description = "SonarQube PostgreSQL password"
  type        = string
  sensitive   = true
  default     = "sonar-password"
}
