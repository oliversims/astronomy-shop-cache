# Open this URL after apply (ExternalDNS must have created the record).
output "argocd_url" {
  description = "Public HTTPS URL for Argo CD"
  value       = "https://${var.hostname}"
}

# Username is admin. Run this in PowerShell to print the initial password.
output "argocd_admin_password_command" {
  description = "Command to print the Argo CD admin password"
  value       = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }"
}
