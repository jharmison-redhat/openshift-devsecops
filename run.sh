#!/bin/bash

thisdir=$(dirname $(realpath $0))
cd "$thisdir"

verbose_flag=''
vault_flag=''
become_flag=''
extra=''
playbook=''
inventory=''

. run_funcs

usage="usage: $(basename $0) [-h|--help] | [-v|--verbose] [-V|--vault] [-b|--become] \\
  [(-e |--extra=)VARS] [(-i |--inventory=)FILE] [(-S |--source=)file/to/source] \\
  [[path/to/]PLAY[.yml]]"


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
                                  one available.
                                NOTE: Playbooks must be in the 'playbooks/'
                                  subdirectory in the same path as this script
                                  to be identified for the menu
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
                extra="$1"
            else
                extra=$(echo "$1" | cut -d= -f2-)
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
                playbook="playbooks/${1}.yml"
            elif [ -f "playbooks/${1}" ]; then
                playbook="playbooks/${1}"
            elif [ -f "${1}" ]; then
                playbook="${1}"
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

if [ -z "$playbook" ]; then
    if [ $(ls playbooks/ | wc -l) -eq 1 ]; then
        playbook="playbooks/$(ls playbooks/)"
    else
        echo 'Choose a play to run:'
        export PS3='> '
        select choice in $(ls playbooks/ | sed 's/\.yml//g'); do
            if [ "$choice" ]; then
                playbook="playbooks/${choice}.yml"
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

if [ -n "$extra" ]; then
    ansible-playbook ${args} -e "$extra" "$playbook"
else
    ansible-playbook ${args} "$playbook"
fi
