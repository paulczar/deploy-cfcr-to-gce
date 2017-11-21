#!/bin/bash

set -e
set -o pipefail

. ./kubo-deploy.env

mkdir -p "${kubo_envs}"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

kubo_env_path="${kubo_envs}/${kubo_env_name}"
state_dir=~/kubo-env/${kubo_env_name}

cd /share/kubo-deployment

echo "====> Prepare local workspace for kubo deployment"

echo "--> Generate a CFCR configuration template"
./bin/generate_env_config "${kubo_envs}" ${kubo_env_name} gcp

echo "--> Apply the default network settings"
/usr/bin/update_gcp_env "${kubo_env_path}/director.yml"

echo "====> Deploy BOSH director"
./bin/deploy_bosh "${kubo_env_path}" ~/terraform.key.json

echo "====> Configure GCP load balancers"

cd /share/kubo-deployment/docs/user-guide/routing/gcp
echo "--> Create the GCP resources for CFCR"
export state_dir=~/kubo-env/${kubo_env_name}
export kubo_terraform_state=${state_dir}/terraform.tfstate

terraform apply \
    -var network=${network} \
    -var projectid=${project_id} \
    -var region=${region} \
    -var prefix=${prefix} \
    -var ip_cidr_range="${subnet_ip_prefix}.0/24" \
    -state=${kubo_terraform_state}

cat << EOF >> ~/kubo-deploy.env
export kubo_terraform_state=${state_dir}/terraform.tfstate
export master_target_pool=$(terraform output -state=${kubo_terraform_state} kubo_master_target_pool)
export kubernetes_master_host=$(terraform output -state=${kubo_terraform_state} master_lb_ip_address)
EOF

. ~/kubo-deploy.env

echo "--> Update the CFCR environment"
/usr/bin/set_iaas_routing "${state_dir}/director.yml"


echo "====> Deploy CFCR"
echo "--> Perform Deployment"
cd /share/kubo-deployment
./bin/deploy_k8s ~/kubo-env/kubo "$cluster_name"

echo "--> Validate Deployment"
./bin/set_kubeconfig ~/kubo-env/kubo "$cluster_name"
kubectl get pods --namespace=kube-system

echo "--> Create Storage Class"
kubectl apply -f https://raw.githubusercontent.com/pivotal-cf-experimental/kubo-ci/master/specs/storage-class-gcp.yml
