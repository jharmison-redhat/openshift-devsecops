if [ "$0" == "$BASH_SOURCE" ]; then
    echo "Please, only source this script. Don't execute it." >&2
    exit 1
fi

tmp_dir=$(dirname $(realpath "$BASH_SOURCE"))/tmp
[ -f "$tmp_dir/../.aws" ] && . "$tmp_dir/../.aws" ||:
echo "$PATH" | grep -qF "$tmp_dir" || export PATH=$tmp_dir:$PATH
export KUBECONFIG=$tmp_dir/auth/kubeconfig

echo "Environment staged." >&2
