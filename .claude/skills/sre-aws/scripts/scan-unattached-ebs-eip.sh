#!/usr/bin/env bash
# Read-only multi-region scan for unattached EBS volumes and unassociated Elastic IPs. Changes nothing.
# Usage: AWS_PROFILE=<profile> ./scan-unattached-ebs-eip.sh [region ...]   (default: all enabled regions)
# Refs (2026-10-16): https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/describe-volumes.html
#                    https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/describe-addresses.html
set -euo pipefail
# shellcheck source=SCRIPTDIR/_guard.sh
source "$(dirname "$0")/_guard.sh"
if [[ $# -gt 0 ]]; then regions=("$@"); else
  read -r -a regions <<< "$(aws_ro ec2 describe-regions --region "${AWS_REGION:-us-east-1}" \
    --filters Name=opt-in-status,Values=opt-in-not-required,opted-in --query 'Regions[].RegionName' --output text)"
fi
printf 'region\ttype\tid\tdetail\n'
for r in "${regions[@]}"; do
  aws_ro ec2 describe-volumes --region "$r" --filters Name=status,Values=available \
    --query 'Volumes[].[VolumeId,Size,VolumeType]' --output text \
    | while read -r id sz vt; do [[ -n "$id" ]] && printf "%s\tebs\t%s\t%sGiB %s\n" "$r" "$id" "$sz" "$vt"; done
  aws_ro ec2 describe-addresses --region "$r" \
    --query 'Addresses[?AssociationId==null].[AllocationId,PublicIp]' --output text \
    | while read -r id ip; do [[ -n "$id" ]] && printf '%s\teip\t%s\t%s\n' "$r" "$id" "$ip"; done
done
