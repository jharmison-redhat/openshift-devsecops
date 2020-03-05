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

`run.sh` was developed on Fedora 30 and 31. All modern testing of it has been done on Fedora 31. The most important part of satisfying dependencies automatically is that you have `dnf` available and a Fedora-like package naming convention. This means that it should operate as expected on RHEL 8, but this has not been tested for validity.

The requirements for running the playbooks and roles have been mostly consolidated into `runreqs.json` and the hashmap should be relatively self-explanitory. If the binaries listed are in your `$PATH`, `run.sh` will not attempt to install them. If they are not, `run.sh` will attempt to install them using `dnf` with `sudo`. This enables running on arbitrary alternative \*NIX platforms, if the binaries are in your path. The absolute most basic requirements are `python` and `jq`, and they are not included in `runreqs.json` as they will not be changing based on the workshop content, but must exist prior to other dependency setup. `run.sh` will attempt to install them both, as well as `pip` in user mode, if they are not available in `$PATH`.

To run the playbooks yourself, using `ansible-playbook` and without `run.sh`, `jq` is not required but the other binaries in the `dnf` key as well as the Python libraries in the `pip` key of `runreqs.json` are all required.

## Basic operation
1. For easiest operation, you should create a file at the project root named `.aws` with the following content:
   ```shell
   export AWS_ACCESS_KEY_ID=<your actual access key ID>
   export AWS_SECRET_ACCESS_KEY=<your actual access key secret>
   ```
   It is in .gitignore, so it won't be committed if you make changes.
1. Open a terminal and change into the project directory. Source `prep.sh`:
   ```shell
   cd openshift-devsecops # or wherever you put it
   . prep.sh
   ```
1. Copy the vars examples and edit them to match your desired environment
   ```shell
   cp vars/provision.example.yml vars/provision.yml
   vi vars/provision.yml # Change the appropriate variables
   cp vars/devsecops.example.yml vars/devsecops.yml
   vi vars/devsecops.yml # Change variables as you desire to enable/disable content
   ```
1. Execute `run.sh` with the names of the playbooks you would like run, in order.
   ```shell
   ./run.sh provision deploy
   ```
1. Wait a while. Currently, in my experience, it takes just under an hour to deploy everything I've made so far.
1. Access the cluster via cli or web console. The `oc` client is downloaded into `tmp` and `prep.sh` has put that into your path. The web console should be available at `https://console.apps.{{ cluster_name }}.{{ openshift_base_domain }}`.
1. When you are ready to tear the cluster down, run the following commands from the project root:
   ```shell
   cd tmp            # this is important for the next command to work correctly
   openshift-install destroy cluster
   ```
   If you attempt to do this from outside of the tmp directory, openshift-install will throw an error. I should probably just add a playbook for it.

## Basic Structure
There are two major playbooks implemented currently:
  - `playbooks/provision.yml`
  - `playbooks/deploy.yml`

There's also a currently-unmaintained playbook that was used at one point to spin up ODH on a cluster built from this repo. It may be further integrated and maintained at a later date, but for now the remains of that work is available at:
  - `playbooks/install_odh.yml`

Additionally, there are two important vars files currently:
  - `vars/provision.yml`
  - `vars/devsecops.yml`

There are a significant number of in-flux roles that are part of building the cluster and workshop content. You should explore individual roles on your own, or look at how the playbooks use them to understand their operation. The intent of the final release of this repo is that the roles will be capable of being developed/maintained independently, and they may be split into separate repositories with role depdendency, git submodules, or some combination of the two used to install them from GitHub or another SCM.

### Playbooks
---
#### playbooks/provision.yml
This playbook will, given access to AWS keys for an administrator account on which Route53 is managing DNS on a hosted zone, provision an OpenShift 4.x cluster using the latest installer for that major.minor release. Additionally, it conducts the following adjustments to the cluster:
  - Create htpasswd-backed users based on the vars provided
  - Delete the kubeadmin default user
  - Generate and apply LetsEncrypt certificates for both the API endpoint and the default certificate for the OpenShift Router
  - Enable Machine and Cluster Autoscalers to allow the cluster to remain as small as possible (two 2xlarge instances as workers by default) until a load requires more nodes to be provisioned.
  - Change the console route to `console.apps.{{ cluster_name }}.{{ openshift_base_domain }}` because `console-openshift-console.apps` was deemed to be _just a bit much_.

Future plans for this playbook:
  - Implement provisioning for other CCSPs (TBD)
  - Better separate the concerns between what we can do with AWS, other CCSPs, and RHPDS-built clusters.

#### playbooks/deploy.yml
This playbook will deploy all of the services to be used in the workshop. As a rule, it uses Operators for the provisioning/management of all services. Where an appropriate Operator was available in the default catalog sources, thosewere used. Where one doesn't exist, they were sourced from Red Hat GPTE published content. Also as a rule, it tries to stand up only one of each service and provision users on each service. The roles have all been designed such that they attempt to deploy sane defaults in the absence of custom variables, but there should be enough configuration available through templated variables that the roles are valuable outside of the scope of this workshop.

The services provided are currently in rapid flux and you should simply look through the listing to see what's applied. For roles to be implemented or changed in the future, please refer to GitHub Issues as these are the tracking mechanism I'm using to keep myself on track.

Right now this playbook is requiring the provision variables be set, and also requesting access to AWS keys. This is expected to change in the future as the concerns are better separated.

### Variable Files
---
There are example files that may be copied and changed for the variable files. Where deemed necessary, the variables are appropriately commented to explain where you should derive their values from, and what they will do for you.
There is currently an open issue regarding what I dislike about the rigid structure of requiring these files in these directories. Some effort will be made at a later date to make their inclusion optional for normal workshop provisioning, and some amount of detection will be implemented to facilitate that.

#### vars/provision.yml
The primary function of these variables is to provide information necessary to the `provision.yml` playbook for deployment and adjustment of the cluster. Future plans for this file align with the future plans for the playbook, intended to enable and facilitate more modularity and allow more infrastrucure platforms. Additionally, those variables identified as necessary for workshop provisioning on top of an established cluster will likely be split out into a third, `common.yml`, vars file.

#### vars/devsecops.yml
This mostly contains switches to enable or disable workshop services and infrastructure. It's also used right now to control from which GitHub project the various GPTE-built operators are sourced.

## Contributing
I welcome pull requests and issues. I want this to become a valuable tool for Red Hatters at all levels to explore or use for their work, and to be a valuable resource for our partners. If there's something that you think I should do that I'm not, or something that's not working the way you think it was intended, please either let me know or fix it, if you're able. I would love to have help, and as long as we're communicating well via GitHub Issues about the direction that something should go, I won't turn away that help. Please, follow the overall design goals if making a pull request.

