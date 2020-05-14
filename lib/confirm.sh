#!/bin/bash

script_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${script_path}/bash_colors.sh

function confirm() {
    if [[ "$1" == "0" || "$1" == "true" || "$1" == "TRUE" ]]; then
        clr_brown "Continue (yes/no)? yes"
        echo "Yes, continue"
        return 0 
    fi

    while true; do
        read -p "$( clr_brown "Continue (yes/no)? " )"  answer
        case "$answer" in 
            [yY][eE][sS]|[yY])
                echo "Yes, continue"
                return 0
                ;;
            [nN][oO]|[nN] )
                echo "No, abort"
                return 1
                ;;
            * )
                echo 'Please answer "yes" to continue or "no" to abort'
                continue
                ;;
        esac
    done
}
