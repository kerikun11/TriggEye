#!/bin/bash

# specify image tag name
TAG="$(basename $(dirname $(readlink -f $0)))" # use current script's directory name

# go to this script directory
cd $(dirname $0)

# prepare log file
LOG_FILE="logs/$(basename $0)-$(date +%Y%m%d-%H%M%S).log"
mkdir -p $(dirname $LOG_FILE)

# logging area
(
    # set to show running command
    set -x

    # show info
    uname -a

    # build (with time profiling)
    time docker build -t "$TAG" "$@" .

) 2>&1 \
| while IFS= read -r line;
do printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line";
done \
| tee -a $LOG_FILE
