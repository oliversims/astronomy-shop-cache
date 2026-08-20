# Open this URL after apply (ExternalDNS must have created the record).
output "grafana_url" {
  description = "Public HTTPS URL for Grafana"
  value       = "https://${var.hostname}"
}

# Username is admin. Run this in PowerShell to print the Grafana password.
output "grafana_admin_password_command" {
  description = "Command to print the Grafana admin password"
  value       = "kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }"
}
