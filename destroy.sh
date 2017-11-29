#!/bin/bash

set -e
set -o pipefail
[[ -n "${DEBUG}" ]] && set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. ./kubo-deploy.env

if [[ -z "${prefix}" ]]; then
  echo "environment variable 'prefix' not set. check kubo-deploy.env."
  exit 1
fi

for app in gcloud terraform parallel; do
  if ! which "${app}" > /dev/null; then
    echo please install "${app}" before running this script
  fi
done

echo "====> Destroy VMs"
gcloud compute instances list --format 'value(name)' --filter labels.deployment=\(bosh,${cluster_name}\) | \
  parallel --willcite 'gcloud compute instances delete --quiet --delete-disks=all {}'
gcloud compute instances list --format 'value(name)' --filter="name~'^${prefix}'" | \
  parallel --willcite 'gcloud compute instances delete --quiet --delete-disks=all {}'

echo "====> Destroy Kubo Network resources"

gcloud compute firewall-rules list --format 'value(name)' --filter="name~'^${prefix}'" | \
  parallel --willcite 'gcloud compute firewall-rules delete --quiet {}'

gcloud compute forwarding-rules list --format 'value(name)' --filter="name~'^${prefix}'" | \
  parallel --willcite 'gcloud compute forwarding-rules delete --quiet --region=${region} {}'

gcloud compute addresses list --format 'value(name)' --filter="name~'^${prefix}'" | \
  parallel --willcite 'gcloud compute addresses delete --quiet {}'

gcloud compute routes list --format 'value(name)' --filter="name~'^(${prefix}|kubernetes-)'" | \
  parallel --willcite 'gcloud compute routes delete --quiet {}'

gcloud compute routes list --format 'value(name)' --filter="name~'^${prefix}'" | \
  parallel --willcite 'gcloud compute routes delete --quiet {}'

gcloud compute target-pools list --format 'value(name)' --filter="name~'^${prefix}'" | \
  parallel --willcite 'gcloud compute target-pools delete --quiet {}'

gcloud compute networks subnets list --format 'value(name)' --filter="name~'^${prefix}'" | \
  parallel --willcite 'gcloud compute networks subnets delete --quiet {}'

gcloud compute networks delete "${prefix}${network}" --quiet


echo "====> remove IAM"
gcloud projects remove-iam-policy-binding "${project_id}" \
      --member serviceAccount:"${service_account_email}" \
      --role roles/owner > /dev/null || echo "."

for role in "roles/compute.instanceAdmin" "roles/compute.networkAdmin" "roles/compute.securityAdmin" "roles/compute.storageAdmin" "roles/iam.serviceAccountActor"; do
gcloud projects remove-iam-policy-binding "${project_id}" \
      --member serviceAccount:"${prefix}kubo@${project_id}.iam.gserviceaccount.com" \
      --role "${role}" > /dev/null || echo "."
done

gcloud iam service-accounts list --format='value(EMAIL)' --filter="email~'^${prefix}'" | \
  parallel --willcite 'gcloud iam service-accounts delete --quiet {}'

[[ -e ~/terraform.key.json ]] && rm ~/terraform.key.json

[[ -e $DIR/kubo-deployment/docs/user-guide/platforms/gcp/*tfstate ]] &&
  rm $DIR/kubo-deployment/docs/user-guide/platforms/gcp/*tfstate
