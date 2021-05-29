#!/bin/sh

# specify image tag name
TAG="$(basename $(dirname $(readlink -f $0)))" # use current script's directory name

# run
docker run --rm -it --runtime nvidia --network host \
    -v $PWD:/workspace -w /workspace \
    $TAG "$@" # pass the arguments as they are
