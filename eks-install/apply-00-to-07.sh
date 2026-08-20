#!/usr/bin/env bash
# Apply stacks 01-vpc → 07-monitoring.
# Prerequisites: AWS credentials on this machine. Apply 00-s3 first, then paste
# the bucket name into every later stack's backend (and remote_state) before
# running this script.
# Run from a machine that can reach the public EKS API (your IP must be in
# 02-eks public_access_cidrs).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "==============================="
echo "STEP-1: Create VPC using Terraform"
echo "==============================="
cd "${ROOT}/01-vpc"
terraform init -reconfigure
terraform apply --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-2: Create EKS using Terraform"
echo "==============================="
cd "${ROOT}/02-eks"
terraform init -reconfigure
terraform apply --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-3: Create ACM using Terraform"
echo "==============================="
cd "${ROOT}/03-acm"
terraform init -reconfigure
terraform apply --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-4: Create ALB Controller using Terraform"
echo "==============================="
cd "${ROOT}/04-alb"
terraform init -reconfigure
terraform apply --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-5: Create ExternalDNS using Terraform"
echo "==============================="
cd "${ROOT}/05-external-dns"
terraform init -reconfigure
terraform apply --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-6: Create Argo CD using Terraform"
echo "==============================="
cd "${ROOT}/06-argocd"
terraform init -reconfigure
terraform apply --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-7: Create monitoring using Terraform"
echo "==============================="
cd "${ROOT}/07-monitoring"
terraform init -reconfigure
terraform apply --auto-approve
sleep 10

echo
echo "Done: 01-vpc → 02-eks → 03-acm → 04-alb → 05-external-dns → 06-argocd → 07-monitoring."
echo "kubectl:  cd ${ROOT}/02-eks && terraform output -raw configure_kubectl"
echo "Argo CD:  cd ${ROOT}/06-argocd && terraform output"
echo "Grafana:  cd ${ROOT}/07-monitoring && terraform output"
