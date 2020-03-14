#!/bin/bash

thisdir=$(dirname $(realpath $0))
cd "$thisdir"

verbose_flag=''
vault_flag=''
become_flag=''
extra=()
playbooks=()
inventory=''

. run_funcs

usage="usage: $(basename $0) [-h|--help] | [-v|--verbose] [-V|--vault] [-b|--become] \\
  [(-e |--extra=)VARS] [(-i |--inventory=)FILE] [(-S |--source=)file/to/source] \\
  [[path/to/]PLAY[.yml]] [PLAY[.yml]]..."


while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            cat << EOF >&2
$usage

    -v|--verbose                Run the ansible-playbook command with the -vvvv
                                  flag to enable extremely verbose output
    -V|--vault                  Ask for the vault password to decrypt your
                                  vaulted variables if there are any
    -b|--become                 Ask for a 'become' or sudoer password, if
                                  necessary in your play
    -e VARS|--extra=VARS        Extra-vars to pass into the playbook
    -i FILE|--inventory=FILE    Path to a file you'd like to use to override the
                                  default inventory, or if specified multiple
                                  times all inventories will be used. (default:
                                  inventory/hosts.yml)
    -S FILE|--source=FILE       Path to a file you'd like sourced prior to the
                                  play run. This can be, for example, a file
                                  that exports other environment variables, or
                                  something that sets up something prior to your
                                  playbook run
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
        -V|--vault)
            vault_flag='--ask-vault-pass'                       ;;
        -b|--become)
            become_flag='-K'                                    ;;
        -e|--extra=*)
            if [ "$1" == '-e' ]; then
                shift
                extra+=('-e' "$1")
            else
                extra+=('-e' $(echo "$1" | cut -d= -f2-))
            fi                                                  ;;
        -i|--inventory=*)
            if [ "$1" == '-i' ]; then
                shift
                inventory="${inventory} -i $1"
            else
                inventory="${inventory} -i "$(echo "$1" | cut -d= -f2-)
            fi                                                  ;;
        -S|--source=*)
            if [ "$1" == "-S" ]; then
                shift
                source "$1"
            else
                source "$(echo $1 | cut -d= -f2-)"
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

if ! install_reqs; then
    echo "Unable to continue running the playbook." >&2
    exit 1
fi

args="$inventory $verbose_flag $become_flag $vault_flag"

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

if [ -f "ansible.cfg" ]; then
    export ANSIBLE_CONFIG="${thisdir}/ansible.cfg"
fi

for playbook in "${playbooks[@]}"; do
    ansible-playbook ${args} "${extra[@]}" "$playbook" || exit $?
done

