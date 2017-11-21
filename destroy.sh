#!/bin/bash

#set -e
#set -o pipefail
[[ -n ${DEBUG} ]] && set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. ./kubo-deploy.env

para() {
  parallel --willcite "$@"
}

for app in gcloud terraform parallel; do
  if ! which "${app}" > /dev/null; then
    echo please install "${app}" before running this script
  fi
done

echo "--> Destroy VMs"
gcloud compute instances list --format 'value(name)' | \
  para 'gcloud compute instances delete --quiet --delete-disks=all {}'

echo "--> Destroy Disks"
gcloud compute disks list --format 'value(name)' | \
  para 'gcloud compute disks delete --quiet {}'


echo "--> Destroy Kubo Network resources"

gcloud compute firewall-rules list --format 'value(name)' | grep "$prefix" | \
  para 'gcloud compute firewall-rules delete --quiet {}'

gcloud compute forwarding-rules list --format 'value(name)' | grep "$prefix" | \
  para 'gcloud compute forwarding-rules delete --quiet --region=${region} {}'

gcloud compute addresses list --format 'value(name)' | grep "$prefix" | \
  para 'gcloud compute addresses delete --quiet {}'

gcloud compute routes list --format 'value(name)' | grep "$prefix" | \
  para 'gcloud compute routes delete --quiet {}'

gcloud compute target-pools list --format 'value(name)' | grep "$prefix" | \
  para 'gcloud compute target-pools delete --quiet {}'

gcloud compute networks subnets list --format 'value(name)' | grep "$prefix" | \
  para 'gcloud compute networks subnets delete --quiet {}'

gcloud compute networks list --format 'value(name)' | grep "$network" &&
  gcloud compute networks delete --quiet "$network"

echo "--> remove IAM"
gcloud projects remove-iam-policy-binding "${project_id}" \
      --member serviceAccount:"${service_account_email}" \
      --role roles/owner || echo "."

gcloud projects remove-iam-policy-binding "${project_id}" \
      --member serviceAccount:"${prefix}kubo@${project_id}.iam.gserviceaccount.com" \
      --role roles/owner || echo "."

gcloud iam service-accounts list --format='value(EMAIL)' | grep "$prefix" | \
  para 'gcloud iam service-accounts delete --quiet {}'

[[ -e ~/terraform.key.json ]] && rm ~/terraform.key.json
