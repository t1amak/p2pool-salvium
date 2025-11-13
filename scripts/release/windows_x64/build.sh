#!/bin/sh
set -eu

# Example usage: ./build.sh v4.9

cd "$(dirname "$0")"

repo_root="$(cd ../../.. && pwd)"

if [ "${2:-}" ]; then
	cpu_set="--cpuset-cpus $2"
else
	cpu_set=""
fi

docker build $cpu_set --build-arg P2POOL_VERSION=$1 -t p2pool_windows_x64_build_$1 -f Dockerfile "$repo_root"

docker create --name p2pool_windows_x64_build_$1_container p2pool_windows_x64_build_$1:latest
docker cp p2pool_windows_x64_build_$1_container:/p2pool/build/p2pool-$1-windows-x64.zip ../p2pool-$1-windows-x64.zip
docker rm p2pool_windows_x64_build_$1_container

docker image rm -f p2pool_windows_x64_build_$1
