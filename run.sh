#!/bin/bash -eu

docker run --rm -it \
    --volume /dev:/dev:rw \
    --privileged \
    --network host \
    --volume $(pwd):/workspace \
    --workdir /workspace \
    --user $(id -u):$(id -g) \
    --volume /etc/passwd:/etc/passwd:ro \
    --volume /etc/group:/etc/group:ro \
    --env DISPLAY \
    --volume $HOME/.Xauthority:$HOME/.Xauthority:ro \
    --group-add video \
    --tmpfs $HOME \
    triggeye \
    ./triggeye -w 640 -h 480 echo hello
