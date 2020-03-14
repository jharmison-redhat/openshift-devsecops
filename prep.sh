if [ "$0" == "$BASH_SOURCE" ]; then
    echo "Please, only source this script. Don't execute it." >&2
    exit 1
fi

# Help us find things
tmp_parent=$(dirname $(realpath "$BASH_SOURCE"))/tmp

# Source AWS exports if available
[ -f "$tmp_parent/../.aws" ] && . "$tmp_parent/../.aws" ||:

# This is the safest way to identify cluster directories (and prevent subshelling exports)
unset cluster_dirs
declare -a cluster_dirs
while IFS= read -r -d $'\0' cluster_dir; do
    cluster_dirs+=("$cluster_dir")
done < <(find "$tmp_parent" -mindepth 1 -maxdepth 1 -type d -print0)

# Validate cluster directories, prompt for inclusion
for cluster_dir in "${cluster_dirs[@]}"; do
    this_cluster=$(echo $cluster_dir | rev | cut -d'/' -f1 | rev)
    echo "Identified presumptive cluster $this_cluster" >&2
    # This means it's probably a cluster directory
    if [ -f "${cluster_dir}/oc" -o -f "${cluster_dir}/openshift-install" -o -f "${cluster_dir}/auth/kubeconfig" ]; then
        # In order to let multiple terminals handle different clusters, we can do this
        read -n1 -p "Do you want to add $this_cluster to PATH and KUBECONFIG (y/n Default: Y)?" add_cluster
        echo
        if [ "${add_cluster^^}" = "Y" -o -z "${add_cluster}" ]; then
            echo "$PATH" | grep -qF "$cluster_dir" || export PATH=$cluster_dir:$PATH
            this_kubeconfig="$cluster_dir/auth/kubeconfig"
            # Set first kubeconfig or append
            if [ -z "$KUBECONFIG" ]; then
                export KUBECONFIG="$this_kubeconfig"
            else
                echo "$KUBECONFIG" | grep -qF "$this_kubeconfig" || export KUBECONFIG="$KUBECONFIG:$this_kubeconfig"
            fi
        elif [ "${add_cluster^^}" = "N" ]; then
            echo "Skipping $this_cluster" >&2
        else
            # Default to yes when no input but bad input = skip to be safe
            echo "Unknown input detected, skipping $this_cluster" >&2
        fi
    else
        echo "$this_cluster doesn't seem to be a cluster-directory, skipping" >&2
    fi
done


echo
echo "KUBECONFIG: $KUBECONFIG" >&2
echo "Environment staged." >&2
