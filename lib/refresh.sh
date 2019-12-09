#!/bin/bash

function refresh() {
    while read line; do
        echo -ne "${line}\033[0K\r"
    done
}
