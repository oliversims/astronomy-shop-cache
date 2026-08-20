#!/usr/bin/env bash
# Destroy stacks 07-monitoring → 00-s3.
# Order is the reverse of apply-00-to-07.sh.
# Run from a machine that can reach the public EKS API (needed until 02-eks is gone).
# 00-s3 is last so remote state stays available for every earlier destroy.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "==============================="
echo "STEP-1: Destroy monitoring using Terraform"
echo "==============================="
cd "${ROOT}/07-monitoring"
terraform init
terraform destroy --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-2: Destroy Argo CD using Terraform"
echo "==============================="
cd "${ROOT}/06-argocd"
terraform init
terraform destroy --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-3: Destroy ExternalDNS using Terraform"
echo "==============================="
cd "${ROOT}/05-external-dns"
terraform init
terraform destroy --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-4: Destroy ALB Controller using Terraform"
echo "==============================="
cd "${ROOT}/04-alb"
terraform init
terraform destroy --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-5: Destroy ACM using Terraform"
echo "==============================="
cd "${ROOT}/03-acm"
terraform init
terraform destroy --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-6: Destroy EKS using Terraform"
echo "==============================="
cd "${ROOT}/02-eks"
terraform init
terraform destroy --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-7: Destroy VPC using Terraform"
echo "==============================="
cd "${ROOT}/01-vpc"
terraform init
terraform destroy --auto-approve
sleep 10

echo
echo "==============================="
echo "STEP-8: Destroy S3 state using Terraform"
echo "==============================="
cd "${ROOT}/00-s3"
terraform init
terraform destroy --auto-approve

echo
echo "Done: destroyed 07-monitoring → 06-argocd → 05-external-dns → 04-alb → 03-acm → 02-eks → 01-vpc → 00-s3."
