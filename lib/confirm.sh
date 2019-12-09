#!/bin/bash

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${SCRIPT_PATH}/bash_colors.sh

function confirm() {
    if [[ "$1" == "0" || "$1" == "true" || "$1" == "TRUE" ]]; then
        clr_brown "Continue (yes/no)? yes"
        echo "Yes, continue"
        return 0 
    fi

    while true; do
        read -p "$( clr_brown "Continue (yes/no)? " )"  ANSWER
        case "${ANSWER}" in 
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
