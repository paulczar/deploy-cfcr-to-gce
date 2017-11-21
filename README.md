# Deploy Cloud Foundry Container Runtime (CFCR) to Google Cloud Platform (GCP)

_Note: Cloud Foundry Container Runtime (CFCR) was formerly known as Kubo and
can safely assume any time Kubo is mentioned it refers to CFCR._

CFCR is a Bosh installed Kubernetes Cluster. Bosh is quite powerful and supports
installing Kubernetes across a number of cloud platforms. This adds flexibility
adds complexity to the installation tooling.

The following instructions and scripts are designed to distill the [instructions](https://docs-cfcr.cfapps.io/installing/gcp/) for installing Cloud Foundry Container Runtime (CFCR) on Google Cloud Platform (GCP) found in the [official documentation](https://docs-kubo.cfapps.io) into something that makes it quite simple to deploy a basic CFCR cluster.

## Getting Started

It is assumed that you have the following installed and set up:

* [Terraform](https://www.terraform.io/downloads.html)
* [gcloud sdk cli](https://cloud.google.com/sdk/downloads)

Don't forget to initialize your [gcloud cli](https://cloud.google.com/sdk/docs/initializing).

## Prepare your workstation

The following was written and tested on an MacBook Pro running OSX Sierra. In
theory it should work just fine from Linux or even a Windows machine.

Clone this git repository:

```
$ git clone https://github.com/paulczar/deploy-cfcr-to-gce.git
$ cd deploy-cfcr-to-gce
```

Have a look at `kube-deploy.env` which contains sane defaults for the deploy.
You shouldn't have to change anything and as you deploy some extra Variables
will populate it that will be generated along the way. If you are redeploying
from scratch you should remove any variables declared in the `# temp` section.

## Deploy the Bastion Server

We'll be deploying BOSH and Kubernetes via a Bastion host in the Google Cloud.
The following script will prepare create the Bastion and put all the right bits
in place and then kick off the BOSH deployment from the Bastion:

```
$ ./deploy.sh
...
...
--> Validate Deployment
Setting the target url: https://10.0.1.252:8844
Login Successful
Cluster "my-cluster" set.
User "my-cluster-admin" set.
Context "kubo-my-cluster" created.
Switched to context "kubo-my-cluster".
Created new kubectl context kubo-my-cluster
Try: kubectl get pods --namespace=kube-system
NAME                        READY     STATUS    RESTARTS   AGE
kube-dns-5d694d9fdf-smdhk   0/3       Pending   0          2h
--> Create Storage Class
storageclass "ci-storage" created
```

The deploy script makes an effort to be idempotent and it should be okay to run it
a second time if it fails the first time. Occasionally the BOSH deployment fails
in which case it should prompt you to try again.

To access your Kubernetes cluster log into the Bastion server and run the following:

```
$ ./bin/set_kubeconfig ~/kubo-env/kubo my-cluster
$ kubectl get pods --namespace=kube-system
```


## Cleanup

The cleanup script attempts to delete all of the google cloud resources created
during the deploy. It's quite possible not everything is cleaned up so you should
verify via the Google Cloud UI afterwards.

While it attempts to clean up just the CFCR bits, its probably a good idea to be
very cautious if running it in an project with other systems running.

```bash
$ ./destroy.sh
--> Destroy VMs
Deleted [https://www.googleapis.com/compute/v1/projects/XXXXX/zones/us-west1-a/instances/my-kubobosh-bastion].
Deleted [https://www.googleapis.com/compute/v1/projects/XXXX/zones/us-west1-a/instances/my-kubonat-instance-primary].
deleted service account [my-kuboterraform@pgtm-pczarkowski.iam.gserviceaccount.com]
deleted service account [my-kubokubo@pgtm-pczarkowski.iam.gserviceaccount.com]
$
```
