#!/bin/bash

thisdir=$(dirname $(realpath $0))
cd "$thisdir"

verbose_flag=''
cluster_kubeconfig=''
extra=()
playbooks=()
inventory=''

usage="usage: $(basename $0) [-h|--help] | [-v|--verbose] [(-e |--extra=)VARS] \\
  (-c |--cluster=)CLUSTER [-k |--kubeconfig=)FILE \\
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

if [ -z "$DEVSECOPS_CLUSTER" ]; then
    echo -e "Error: You must specify a cluster.\n$usage" >&2
elif [ ! -d "vars/$DEVSECOPS_CLUSTER" ]; then
    echo -e "Error: You must create a subdirectory in $(pwd)/vars named $cluster with common.yml, devsecops.yml, and provision.yml in it to pass into the container.\n$usage" >&2
fi

args="$verbose_flag"

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

if which podman &>/dev/null; then
    runtime=podman
    run_args="-it --rm -v ./tmp:/app/tmp:shared -v ./vars/$DEVSECOPS_CLUSTER:/app/vars:shared,ro --label=disable --privileged"
elif which docker &>/dev/null; then
    runtime=docker
    run_args="-it --rm -v ./tmp:/app/tmp -v ./vars/$DEVSECOPS_CLUSTER:/app/vars:ro --security-opt label=disabled --privileged"
else
    echo "A container runtime is necessary to execute these playbooks." >&2
    echo "Please install podman or docker." >&2
    exit 1
fi

if echo "${playbooks[*]}" | grep -qF provision || echo "${playbooks[*]}" | grep -qF destroy; then
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        read -p "Enter your AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
    fi
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        read -sp "Enter your AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
    fi
fi

$runtime build . -t devsecops-$DEVSECOPS_CLUSTER

if [ "$cluster_kubeconfig" ]; then
    cluster_name=$(awk '/^cluster_name:/{print $2}' vars/$DEVSECOPS_CLUSTER/common.yml)
    openshift_base_domain=$(awk '/^openshift_base_domain:/{print $2}' vars/$DEVSECOPS_CLUSTER/common.yml)
    mkdir -p tmp/$cluster_name.$openshift_base_domain/auth
    cp "$cluster_kubeconfig" "tmp/$cluster_name.$openshift_base_domain/auth/kubeconfig"
fi

for playbook in "${playbooks[@]}"; do
    $runtime run ${run_args} devsecops-$DEVSECOPS_CLUSTER ${args} "${extra[@]}" "$playbook" || exit $?
done
