#!/bin/bash
set -euo pipefail

CLANG_VERSION=21.1.5
MACOSX_SDK_VERSION=26.0
OSXCROSS_VERSION=7e8a4d170cc6bda1f0a32f5dc5f6ace4676baf98

echo "Install prerequisites"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -yq --no-install-recommends
apt-get install -yq --no-install-recommends \
  autoconf \
  automake \
  bison \
  binutils-mingw-w64-x86-64 \
  build-essential \
  bzip2 \
  ca-certificates \
  clang \
  cmake \
  curl \
  file \
  flex \
  g++-mingw-w64-x86-64 \
  gcc-mingw-w64-x86-64 \
  gawk \
  gettext \
  git \
  libbz2-dev \
  libedit-dev \
  liblzma-dev \
  libsqlite3-dev \
  libssl-dev \
  libtool \
  libxml2-dev \
  zlib1g-dev \
  lld \
  make \
  mingw-w64-tools \
  ninja-build \
  patch \
  pkg-config \
  p7zip-full \
  python3 \
  rsync \
  texinfo \
  unzip \
  xz-utils \
  zip

rm -rf /var/lib/apt/lists/*

update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

cd /root

echo "Fetch LLVM/Clang ${CLANG_VERSION} sources"

git clone --depth 1 --branch llvmorg-$CLANG_VERSION https://github.com/llvm/llvm-project.git

cd llvm-project
mv /clang_version.patch .
git apply --verbose --ignore-whitespace clang_version.patch

mkdir build
cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="clang;lld;libc" \
  -DLLVM_APPEND_VC_REV=OFF \
  -DLLVM_VERSION_SUFFIX="_p2pool" \
  -DLIBC_WNO_ERROR=ON \
  -DCMAKE_INSTALL_PREFIX=/usr/local ../llvm
ninja
ninja install

cd ..
mkdir build_runtimes
cmake -G Ninja -S runtimes -B build_runtimes \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++
ninja -C build_runtimes cxx cxxabi unwind
ninja -C build_runtimes install

cd /root

echo "Prepare macOS SDK ${MACOSX_SDK_VERSION}"

curl -L -o MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz \
  https://github.com/joseluisq/macosx-sdks/releases/download/${MACOSX_SDK_VERSION}/MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz

git clone https://github.com/tpoechtrager/osxcross.git
cd osxcross
git checkout ${OSXCROSS_VERSION}
mkdir -p tarballs
mv /root/MacOSX${MACOSX_SDK_VERSION}.sdk.tar.xz tarballs/

TARGET_DIR=/usr/local OSX_VERSION_MIN=10.15 UNATTENDED=1 ./build.sh
./build_compiler_rt.sh

cd /root

echo "Clean temporary files"

rm -rf /root/*

echo "All done"
