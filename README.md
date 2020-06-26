# OpenShift DevSecOps Workshop
---

### **Note**: This is a temporary README to support testing and demonstration of the status of the repository, it is not the final intended README.

## Design Goals
Several design goals were set in place before this started, and they have evolved somewhat as the work has gone on.
  - Every role should be useful outside of the context of this workshop
  - Every interaction with OpenShift should be done via the Kubernetes API, using the Ansible `k8s` module, except where it is impractical, to best support declarative configuration and enable fault tolerance and recovery from failures.
  - Everywhere that an action is not natively idempotent (ex: `shell` module), effort should be made to make it idempotent and report appropriate status back to Ansible.
      (Any failures at all due to network conditions, timing problems, etc. should be 100% resolvable by running the exact same playbook without introducing new errors)
  - Everything should be OpenShift 4.x native. This means preferring built-in functionality over third-party functionality, and it means using Operators as the primary deployment/management mechanism.
  - There should be zero interaction required from the time you start to deploy the cluster to the time that the workshop is available for use. Anywhere that automation can make a decision about setting something up, it should have a variable available to change its behavior but assume a sane default.
  - Readability is fundamentally important and any time that something is deemed to be too difficult to understand (large in-line Jinja or JMESPath, for example), it should be separated to be easier to understand.

## Supported Operating Systems
Right now, `run.sh` is the primary mechanism for executing the playbooks. It provides the appropriate context and control for chaining playbooks together locally, as well as ensuring that prerequisites for the roles and playbooks are implemented on your system. You can use `run.sh` on unsupported platforms by ensuring the dependencies are met before running it, or you can use it on a supported platform to have it do the work for you.

`run.sh` was developed on Fedora 30 and 31. All modern testing of it has been done on Fedora 32. The most important part of satisfying dependencies automatically is that you have `dnf` available and a Fedora-like package naming convention. This means that it should operate as expected on RHEL 8, but this has not been tested for validity.

The requirements for running the playbooks and roles have been mostly consolidated into `runreqs.json` and the hashmap should be relatively self-explanitory. If the binaries listed are in your `$PATH`, `run.sh` will not attempt to install them. If they are not, `run.sh` will attempt to install them using `dnf` with `sudo`. This enables running on arbitrary alternative \*NIX platforms, if the binaries are in your path. The absolute most basic requirements are `python` and `jq`, and they are not included in `runreqs.json` as they will not be changing based on the workshop content, but must exist prior to other dependency setup. `run.sh` will attempt to install them both, as well as `pip` in user mode, if they are not available in `$PATH`.

To run the playbooks yourself, using `ansible-playbook` and without `run.sh`, `jq` is not required but the other binaries in the `dnf` key as well as the Python libraries in the `pip` key of `runreqs.json` are all required.

## Alternative, container-based usage
`run-container.sh` has been developed to use the Dockerfile present to run the playbooks inside a RHEL 8 UBI container image. This means you can use run-container.sh to package a new container image on the fly with your changes to the repository, satisfying dependencies, and then map tmp and vars in to the container. In order to enable multiple clusters being run with multiple containers, `run-container.sh` requires some alternative variables to be set.

```shell
usage: run-container.sh [-h|--help] | [-v|--verbose] [(-e |--extra=)VARS] \
  (-c |--cluster=)CLUSTER [-k |--kubeconfig=)FILE \
  [[path/to/]PLAY[.yml]] [PLAY[.yml]]...
```

You should specify `-c CLUSTER` or `--cluster=CLUSTER` to define a container-managed cluster with a friendly name of CLUSTER. In this case, the container images will be tagged as `devsecops-CLUSTER:latest` and when executed, vars will be mapped in from `vars/CLUSTER/`, expecting to be their default names of `common.yml`, `devsecops.yml`, etc. as needed. In this configuration, if you have a local `~/.kube/config` that you have a cached login (for example, as `opentlc-mgr`, you should pass the path to that file with `-k ~/.kube/config` or `--kubeconfig=~/.kube/config`. `run-container.sh` will copy that file into the `tmp/` directory in the appropriate place for your cluster, and `kubeconfig` should _**not be changed**_ from the DEFAULT of `{{ tmp_dir }}/auth/kubeconfig` in `vars/CLUSTER/common.yml`. Because `run-container.sh` stages the kubeconfig in this way, the cached logins from the playbooks will not back-propogate to your local `~/.kube/config`, so follow-on execution of `oc` or `kubectl` on your host system will not 

## Basic operation

### Deployment of an OpenShift cluster

1. For easiest operation, you should create a file at the project root named `.aws` with the following content:
   ```shell
   export AWS_ACCESS_KEY_ID=<your actual access key ID>
   export AWS_SECRET_ACCESS_KEY=<your actual access key secret>
   ```
   It is in .gitignore, so you won't be committing secrets if you make changes.
1. Open a terminal and change into the project directory. Source `prep.sh`:
   ```shell
   cd openshift-devsecops # or wherever you put the project root
   . prep.sh
   ```
1. Copy the vars examples and edit them to match your desired environment
   ```shell
   cp vars/common.example.yml vars/common.yml
   vi vars/common.yml               # Change the appropriate variables
   cp vars/provision.example.yml vars/provision.yml
   vi vars/provision.yml            # Change the appropriate variables
   ```
1. Execute `run.sh` with the names of the playbooks you would like run, in order.
   ```shell
   ./run.sh provision
   ```
1. Wait a while. Currently, in my experience, it takes about 35-45 minutes to deploy a cluster.
### Deployment of workshop on an existing cluster
1. Open a terminal and change into the project directory. Copy the vars examples and edit them to match your desired environment.
   ```shell
   cd openshift-devsecops # or wherever you put the project root
   cp vars/common.example.yml vars/common.yml
   vi vars/common.yml               # Change the appropriate variables
   cp vars/devsecops.example.yml vars/devsecops.yml
   vi vars/devsecops.yml            # Change the appropriate variables
   ```
1. Execute `run.sh` with the names of the devsecops playbook
   ```shell
   ./run.sh devsecops
   ```
1. Wait a while. Currently, in my experience, it takes about 15-30 minutes to deploy everything I've made so far.
### Alternatively, deploy a cluster and the workshop content at once
1. Do all of the above steps for both parts at once.
   ```shell
   cd openshift-devsecops # or wherever you put the project root
   . prep.sh
   cp vars/common.example.yml vars/common.yml
   vi vars/common.yml               # Change the appropriate variables
   cp vars/provision.example.yml vars/provision.yml
   vi vars/provision.yml            # Change the appropriate variables
   cp vars/devsecops.example.yml vars/devsecops.yml
   vi vars/devsecops.yml            # Change the appropriate variables
   ./run.sh provision devsecops
   ```
1. Wait a while. Currently, in my experience, it takes about an hour to deploy a cluster and everything I've made so far.
### Access the workshop services if you deployed the cluster from this repo
1. Access the cluster via cli or web console. If this repo deployed your cluster, the `oc` client is downloaded into `tmp`, in a directory named after the cluster, and `prep.sh` can put that into your path. The web console should be available at `https://console.apps.{{ cluster_name }}.{{ openshift_base_domain }}`. If you have recently deployed a cluster, you can update kubeconfig paths and $PATH for running binaries with the following:
   ```shell
   cd openshift-devsecops # or wherever you put the project root
   . prep.sh
   ```
   prep.sh is aware of multiple clusters and will let you add to PATH and KUBECONFIG on a per-cluster basis in multiple terminals if you would like.
1. If you deployed the cluster with this repo, when you are ready to tear the cluster down, run the following commands from the project root:
   ```shell
   cd openshift-devsecops # or wherever you put the project root
   . prep.sh
   ./run.sh destroy
   ```
   If you are using multiple clusters or otherwise non-default vars files locations, you can specify a common.yml path (e.g. with `-e @vars/my_common.yml`) to destroy a specific cluster.

## Basic Structure
There are three major playbooks implemented currently:
  - `playbooks/provision.yml`
  - `playbooks/devescops.yml`
  - `playbooks/destroy.yml`

Additionally, there are three important vars files currently:
  - `vars/provision.yml`
  - `vars/devsecops.yml`
  - `vars/common.yml`

There are a significant number of in-flux roles that are part of building the cluster and workshop content. You should explore individual roles on your own, or look at how the playbooks use them to understand their operation. The intent of the final release of this repo is that the roles will be capable of being developed/maintained independently, and they may be split into separate repositories with role depdendency, git submodules, or some combination of the two used to install them from GitHub or another SCM.

### Playbooks
---
#### playbooks/provision.yml
This playbook will, given access to AWS keys for an administrator account on which Route53 is managing DNS, provision an OpenShift 4.x cluster using the latest installer for the specified major.minor release.
Future plans for this playbook:
  - Implement provisioning for other CCSPs (TBD)

#### playbooks/devescops.yml
This playbook will deploy all of the services to be used in the workshop. First it adjusts the cluster to be ready to accept workshop content by doing the following:
  - Create htpasswd-backed users based on the vars provided
  - Delete the kubeadmin default user
  - Generate and apply LetsEncrypt certificates for both the API endpoint and the default certificate for the OpenShift Router (If you have AWS keys sourced or included in vars)
  - Enable Machine and Cluster Autoscalers to allow the cluster to remain as small as possible (two 2xlarge instances as workers by default) until a load requires more nodes to be provisioned.
  - Change the console route to `console.apps.{{ cluster_name }}.{{ openshift_base_domain }}` because `console-openshift-console.apps` was deemed to be _just a bit much_.

As a rule, it uses Operators for the provisioning/management of all services. Where an appropriate Operator was available in the default catalog sources, those were used. Where one doesn't exist, they were sourced from Red Hat GPTE published content. Also as a rule, it tries to stand up only one of each service and provision users on each service. The roles have all been designed such that they attempt to deploy sane defaults in the absence of custom variables, but there should be enough configuration available through templated variables that the roles are valuable outside of the scope of this workshop.

The services provided are currently in rapid flux and you should simply look through the listing to see what's applied. For roles to be implemented or changed in the future, please refer to GitHub Issues as these are the tracking mechanism I'm using to keep myself on track.

#### playbooks/destroy.yml
This playbook will, provided a common.yml, identify if openshift-install was run from this host and confirm you would like to remove this cluster. It will completely tear the cluster down, and remove everything from the temporary directory for this cluster.

### Variable Files
---
There are example files that may be copied and changed for the variable files. Where deemed necessary, the variables are appropriately commented to explain where you should derive their values from, and what they will do for you.
If you do not have them named exactly as they are shown, as long as you include a vars_file that sets the <vars_type>_included (eg common_included) using `-e` on the `run.sh` or `ansible-playbook` command line. This means you can name the files differently, and deploy multiple clusters at once. A hypothetical multi-cluster deployment workflow could be like this:
   ```shell
   cd openshift-devsecops # or wherever you put the project root
   . prep.sh

   # Deploy cluster 1
   cp vars/common.example.yml vars/common_cluster1.yml
   vi vars/common_cluster1.yml               # Change the appropriate variables
   cp vars/provision.example.yml vars/provision_cluster1.yml
   vi vars/provision_cluster1.yml            # Change the appropriate variables
   cp vars/devsecops.example.yml vars/devsecops_cluster1.yml
   vi vars/devsecops_cluster1.yml            # Change the appropriate variables
   ./run.sh provision devsecops -e @vars/common_cluster1.yml -e @vars/provision_cluster1.yml -e @vars/devsecops_cluster1.yml

   # Deploy cluster 2
   cp vars/common.example.yml vars/common_cluster2.yml
   vi vars/common_cluster2.yml               # Change the appropriate variables
   cp vars/provision.example.yml vars/provision_cluster2.yml
   vi vars/provision_cluster2.yml            # Change the appropriate variables
   cp vars/devsecops.example.yml vars/devsecops_cluster2.yml
   vi vars/devsecops_cluster2.yml            # Change the appropriate variables
   ./run.sh provision devsecops -e @vars/common_cluster2.yml -e @vars/provision_cluster2.yml -e @vars/devsecops_cluster2.yml
   ```

#### vars/common.yml
These variables include things that are important for both an RHPDS-deployed cluster and a cluster deployed from this project. They either define where the cluster is for connection, or they define how to deploy and later connect to the cluster. For clusters created with this project, it also indicates how to destroy the cluster.

#### vars/provision.yml
The primary function of these variables is to provide information necessary to the `provision.yml` playbook for deploymen of the cluster. Future plans for this file align with the future plans for the playbook, intended to enable more infrastrucure platforms.

#### vars/devsecops.yml
This mostly contains switches to enable or disable workshop services and infrastructure. It's also used right now to control from which GitHub project the various GPTE-built operators are sourced.

## Contributing
I welcome pull requests and issues. I want this to become a valuable tool for Red Hatters at all levels to explore or use for their work, and to be a valuable resource for our partners. If there's something that you think I should do that I'm not, or something that's not working the way you think it was intended, please either let me know or fix it, if you're able. I would love to have help, and as long as we're communicating well via GitHub Issues about the direction that something should go, I won't turn away that help. Please, follow the overall design goals if making a pull request.
