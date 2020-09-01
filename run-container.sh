#!/bin/bash

cd $(dirname $(realpath $0))

verbose_flag=''
cluster_kubeconfig=''
force_kubeconfig=''
extra=()
playbooks=()
inventory=''

usage="usage: $(basename $0) [-h|--help] | [-v|--verbose] [(-e |--extra=)VARS] \\
  (-c |--cluster=)CLUSTER [-k |--kubeconfig=)FILE [-f|--force] \\
  [[path/to/]PLAY[.yml]] [PLAY[.yml]]..."


while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            cat << EOF >&2
$usage

    -v|--verbose                Run the ansible-playbook command with the -vvvv
                                  flag to enable extremely verbose output
    -e VARS|--extra=VARS        Extra-vars to pass into the playbook
    -c CLUSTER|--cluster=CLUSER Defines the name of the cluster, for the vars
                                  directory and container image name.
    -k FILE|--kubeconfig=FILE   Set a path to a kubeconfig on your host system
                                  to pass into the container image. It will be
                                  copied into the tmp directory for this cluster
                                  prior to bind-mounting the tmp directory.
    -f|--force                  Force overwrite the kubeconfig if it already
                                  exists and you have specified it.
    PLAY[.yml]                  You can specify the file name of a playbook
                                  (with or without the .yml extension) to run.
                                  If omitted, you will be presented with a menu
                                  to select your play from if there is more than
                                  one available. If your playbook is outside of
                                  the directory 'playbooks/', you can specify
                                  the absolute path or the path relative to
                                  run.sh. Multiple playbooks may be specified,
                                  and they will be run sequentially (halting if
                                  any playbook fails).
                                NOTE: Playbooks must be in the 'playbooks/'
                                  subdirectory in the same path as this script
                                  to be identified by the menu presented if none
                                  are provided on the command line.
EOF
        exit                                                    ;;
        -v|--verbose)
            verbose_flag='-vvvv'                                ;;
        -e|--extra=*)
            if [ "$1" == '-e' ]; then
                shift
                extra+=('-e' "$1")
            else
                extra+=('-e' $(echo "$1" | cut -d= -f2-))
            fi                                                  ;;
        -c|--cluster=*)
            if [ "$1" == '-c' ]; then
                shift
                DEVSECOPS_CLUSTER="$1"
            else
                DEVSECOPS_CLUSTER=$(echo "$1" | cut -d= -f2-)
            fi                                                  ;;
        -k|--kubeconfig=*)
            if [ "$1" == '-k' ]; then
                shift
                cluster_kubeconfig="$1"
            else
                cluster_kubeconfig=$(echo "$1" | cut -d= -f2-)
            fi                                                  ;;
        -f|--force)
            force_kubeconfig=true                               ;;
        *)
            if [ -f "playbooks/${1}.yml" ]; then
                playbooks+=("playbooks/${1}.yml")
            elif [ -f "playbooks/${1}" ]; then
                playbooks+=("playbooks/${1}")
            elif [ -f "${1}" ]; then
                playbooks+=("${1}")
            else
                echo -e "Error: $1 appears to be an invalid playbook.\n$usage" >&2
                exit 1
            fi                                                  ;;
    esac
    shift
done

# You have to specify a cluster name, either via export or arg
if [ -z "$DEVSECOPS_CLUSTER" ]; then
    echo -e "Error: You must specify a cluster.\n$usage" >&2
    exit 2
elif [ ! -d "vars/$DEVSECOPS_CLUSTER" ]; then
    echo -e "Error: You must create a subdirectory in $PWD/vars named $cluster with common.yml, devsecops.yml, and provision.yml in it (as needed by your playbooks) to pass into the container.\n$usage" >&2
    exit 3
fi

args="$verbose_flag"

# Find a playbook if you didn't specify one
if [ -z "${playbooks[*]}" ]; then
    if [ $(ls playbooks/ | wc -l) -eq 1 ]; then
        playbooks=("playbooks/$(ls playbooks/)")
    else
        echo 'Choose a play to run:'
        export PS3='> '
        select choice in $(ls playbooks/ | sed 's/\.yml//g'); do
            if [ "$choice" ]; then
                playbooks=("playbooks/${choice}.yml")
                break
            else
                echo "Invalid selection, $REPLY, please select an index position from above." >&2
            fi
        done
    fi
fi

# Identify our container runtime and differences in arguments between them
if which podman &>/dev/null; then
    runtime=podman
    run_args="-v ./tmp:/app/tmp:shared -v ./vars/$DEVSECOPS_CLUSTER:/app/vars:shared,ro --label=disable"
elif which docker &>/dev/null; then
    runtime=docker
    run_args="-v $PWD/tmp:/app/tmp -v $PWD/vars/$DEVSECOPS_CLUSTER:/app/vars:ro --security-opt label=disabled"
else
    echo "A container runtime is necessary to execute these playbooks." >&2
    echo "Please install podman or docker." >&2
    exit 1
fi

# Some operations need AWS environment variables specified.
if echo "${playbooks[*]}" | grep -qF provision || echo "${playbooks[*]}" | grep -qF destroy; then
    # If they're not exported, we'll ask for them.
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        read -p "Enter your AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
    fi
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        read -sp "Enter your AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
    fi
fi

# This builds the container image with the current codebase but no bind mounts
$runtime build . -t devsecops-$DEVSECOPS_CLUSTER

# Now it's time to figure out things about your bind mounts
cluster_name=$(awk '/^cluster_name:/{print $2}' vars/$DEVSECOPS_CLUSTER/common.yml)
openshift_base_domain=$(awk '/^openshift_base_domain:/{print $2}' vars/$DEVSECOPS_CLUSTER/common.yml)
full_cluster_name="$cluster_name.$openshift_base_domain"
mkdir -p tmp/$full_cluster_name/auth

# Try to fix a borked kubeconfig for container runs
sed -i 's/^kubeconfig:.*$/kubeconfig: '"'"'\{\{ tmp_dir \}\}\/auth\/kubeconfig'"'"'/g' vars/$DEVSECOPS_CLUSTER/common.yml &>/dev/null ||:
# Try to fix a borked oc_cli for container runs
sed -i 's/^oc_cli:.*$/oc_cli: '"'"'\/usr\/local\/bin\/oc'"'"'/g' vars/$DEVSECOPS_CLUSTER/common.yml &>/dev/null ||:

if [ "$cluster_kubeconfig" ]; then
    if [ -r "tmp/$full_cluster_name/auth/kubeconfig" -a -z "$force_kubeconfig" ]; then
        echo "[WARN] KUBECONFIG was specified, but already exists at $(pwd)/tmp/$full_cluster_name/auth/kubeconfig" >&2
        echo "Not overwriting! If you want to overwrite it, please remove it or include the '--force' argument." >&2
    else
        cp "$cluster_kubeconfig" "tmp/$full_cluster_name/auth/kubeconfig"
    fi
elif [ -r "tmp/$full_cluster_name/auth/kubeconfig" ]; then
    # Everything is wonderful now (maybe)
    echo >/dev/null
elif echo "${playbooks[*]}" | grep -qF provision; then
    # We'll make our own kubeconfig
    echo >/dev/null
elif [ -r ~/.kube/config ]; then
    echo "[WARN] No KUBECONFIG specified, not provisioning cluster. Grabbing default from $(realpath ~/.kube/config)." >&2
    cp "$(realpath ~/.kube/config)" "tmp/$full_cluster_name/auth/kubeconfig"
else
    echo -e "No KUBECONFIG specified, none in default location. Cowardly aborting.\n$usage" >&2
    exit 4
fi

# Serially iterate over every playbook specified
for playbook in "${playbooks[@]}"; do
    # `-it`
    # We also want to guarantee a TTY for possible prompts
    # `--rm`
    # We want the containers themselves to remain ephemeral
    # `-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY`
    # We can just export AWS variables directly, it won't hurt
    # `--privileged`
    # We're just using the container for runtime environment, not privilege
    #   seperation, so give it all we've got
    # `${run_args}`
    # These are inherited above to account for the differences between docker
    #   and podman, specifically around how they handle SELinux (if present)
    #   and bind mounts.
    # `devsecops-$DEVSECOPS_CLUSTER`
    # This is the name of the container image we built above
    # <everything else>
    # These are passed as args to ansible-playbook inside the container.
    $runtime run -it --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
        --privileged ${run_args} devsecops-$DEVSECOPS_CLUSTER \
        ${args} "${extra[@]}" "$playbook" || exit $?
done
