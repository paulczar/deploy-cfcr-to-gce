#!/bin/bash

set -e
set -o pipefail

[[ -n ${DEBUG} ]] && set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for app in gcloud terraform parallel; do
  if ! which "${app}" > /dev/null; then
    echo please install "${app}" before running this script
  fi
done

if ! gcloud config get-value project > /dev/null; then
  echo please authenticate gcloud cli before running this script
fi

. ${DIR}/kubo-deploy.env

echo "====> Set Environment Variables"
project_id=$(gcloud config get-value project)
service_account_email=${prefix}terraform@$(gcloud config get-value project).iam.gserviceaccount.com

cat << EOF >> ./kubo-deploy.env
export project_id=$(gcloud config get-value project)
export service_account_email=${prefix}terraform@$(gcloud config get-value project).iam.gserviceaccount.com
EOF

echo "====> Enable gcloud APIs"
echo "--> Enable Cloud Resource Manager API"
gcloud services list | grep cloudresourcemanager || \
  gcloud services enable cloudresourcemanager.googleapis.com
echo "--> Enable IAM API"
gcloud services list | grep iam || \
  gcloud services enable iam.googleapis.com

echo "====> Set gcloud region (${region}) and zone (${zone})"
gcloud config set compute/zone ${zone}
gcloud config set compute/region ${region}

echo "====> Create VPC (${prefix}${network})"
gcloud compute networks describe "${prefix}${network}" > /dev/null 2>&1 || \
  gcloud compute networks create "${prefix}${network}" --subnet-mode=custom

echo "====> Create gcloud credentials for Terraform"
gcloud iam service-accounts create ${prefix}terraform || echo .
gcloud iam service-accounts keys create ~/terraform.key.json \
  --iam-account ${service_account_email}
gcloud projects add-iam-policy-binding ${project_id} \
  --member serviceAccount:${service_account_email} \
  --role roles/owner || echo .
export GOOGLE_CREDENTIALS=$(cat ~/terraform.key.json)


echo "====> Download kubo deployment if not present"
if [[ ! -e kubo-deployment ]]; then
echo "--> Downloading and unpacking kubo deployment"
  curl -sSL ${kubo_deployment} | tar xzf -
fi

cd kubo-deployment
[[ -e .git ]] && rm -rf .git

cd docs/user-guide/platforms/gcp

echo "====> Deploying Bastion Server"
if ! gcloud compute instances describe "${prefix}bosh-bastion" > /dev/null 2>&1; then
  echo "--> Initialize Terraform"
  terraform init
  echo "--> Apply Terraform"
  terraform apply \
      -var service_account_email="${service_account_email}" \
      -var projectid="${project_id}" \
      -var network="${prefix}${network}" \
      -var region="${region}" \
      -var prefix="${prefix}" \
      -var zone="${zone}" \
      -var subnet_ip_prefix="${subnet_ip_prefix}"
fi
cd ${DIR}
echo "---> Wait for Bastion to be ready"
while ! gcloud compute ssh "${prefix}bosh-bastion" --zone ${zone} --command="which credhub > /dev/null"; do
  echo -n .
  sleep 5
done
echo .
echo "====> Bastion install complete"
echo
echo
echo "====> Deploy BOSH"
echo "--> Upload files to Bastion"
echo "********************************************************"
echo "* if gcloud asks you to create a keypair               *"
echo "* create one without a passphrase.                     *"
echo "********************************************************"
echo
while ! gcloud compute scp ${DIR}/deploy-kubo.sh ${DIR}/kubo-deploy.env ~/terraform.key.json "${prefix}bosh-bastion":./ --zone ${zone}; do
  echo -n .
  sleep 5
done
echo "--> SSH into Bastion and kick off deploy script"

if ! gcloud compute ssh "${prefix}bosh-bastion" --zone "${zone}" \
  --command="./deploy-kubo.sh"; then

  echo "If the bosh deploy failed you can safely rerun deploy.sh or run:"
  echo "gcloud compute ssh \"${prefix}bosh-bastion\" --zone \"${zone}\" --command=\"./deploy-kubo.sh\""
fi
