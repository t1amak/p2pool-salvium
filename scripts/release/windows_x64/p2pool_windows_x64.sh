#!/bin/sh
set -e

cd /p2pool

PATCH_TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$PATCH_TMP_ROOT"' EXIT
# Copy patches before checkout so they survive switching to older tags.
cp -r patches "$PATCH_TMP_ROOT/"
PATCH_DIR="$PATCH_TMP_ROOT/patches"

git fetch --jobs=$(nproc)
git checkout $2
git submodule update --recursive --jobs $(nproc)

export TZ=UTC0

BUILD_TIMESTAMP=$(git show --no-patch --format=%ct $2)
CURRENT_DATE=$(date -u -d @$BUILD_TIMESTAMP +"%Y-%m-%d")
CURRENT_TIME=$(date -u -d @$BUILD_TIMESTAMP +"%H:%M:%S")
TOUCH_DATE=$(date -u -d @$BUILD_TIMESTAMP +"%Y%m%d%H%M.%S")

flags_size="-ffunction-sections -fdata-sections -Wl,-s -Wl,--gc-sections"
flags_datetime="-D__DATE__=\"\\\"$CURRENT_DATE\\\"\" -D__TIME__=\"\\\"$CURRENT_TIME\\\"\" -Wno-builtin-macro-redefined"

MINGW_SYSROOT="$(x86_64-w64-mingw32-g++ -print-sysroot 2>/dev/null || true)"
if [ -z "$MINGW_SYSROOT" ]; then
	for candidate in /usr/x86_64-w64-mingw32 /usr/local/x86_64-w64-mingw32; do
		if [ -d "$candidate/include" ]; then
			MINGW_SYSROOT="$candidate"
			break
		fi
	done
fi

flags_sysroot=""
LIBGCC_DIR=""

if [ -n "$MINGW_SYSROOT" ]; then
	flags_sysroot="--sysroot=$MINGW_SYSROOT"
	# Fix mingw-w64 headers for clang: skip redefining __cpuidex when clang
	# already provides one via its cpuid.h.
	if [ -f "$PATCH_DIR/mingw/clang-cpuidex.patch" ] && [ -d "$MINGW_SYSROOT/include" ]; then
		cd "$MINGW_SYSROOT"
		patch --follow-symlinks -N -p1 < "$PATCH_DIR/mingw/clang-cpuidex.patch" || true
		cd /p2pool
	fi

	if [ -x "$MINGW_SYSROOT/bin/x86_64-w64-mingw32-g++" ]; then
		MINGW_LIBGCC="$("$MINGW_SYSROOT/bin/x86_64-w64-mingw32-g++" --print-libgcc-file-name 2>/dev/null || true)"
	fi
fi

if [ -z "$MINGW_LIBGCC" ] && command -v x86_64-w64-mingw32-g++ >/dev/null 2>&1; then
	MINGW_LIBGCC="$(x86_64-w64-mingw32-g++ --print-libgcc-file-name 2>/dev/null || true)"
fi
if [ -n "$MINGW_LIBGCC" ]; then
	LIBGCC_DIR="$(dirname "$MINGW_LIBGCC")"
	GCC_TOOLCHAIN="$LIBGCC_DIR"
fi

flags_libs="--target=x86_64-pc-windows-gnu $flags_sysroot -Os -flto -Wl,/timestamp:$BUILD_TIMESTAMP -fuse-ld=lld -w $flags_size $flags_datetime"

flags_p2pool="--target=x86_64-pc-windows-gnu $flags_sysroot -Wl,/timestamp:$BUILD_TIMESTAMP -fuse-ld=lld -femulated-tls -Wno-unused-command-line-argument -Wno-unknown-attributes $flags_size $flags_datetime"

if [ -n "$LIBGCC_DIR" ]; then
	flags_libs="$flags_libs -L$LIBGCC_DIR"
	flags_p2pool="$flags_p2pool -L$LIBGCC_DIR"
fi

if [ -n "$GCC_TOOLCHAIN" ]; then
	flags_libs="--gcc-toolchain=$GCC_TOOLCHAIN $flags_libs"
	flags_p2pool="--gcc-toolchain=$GCC_TOOLCHAIN $flags_p2pool"
	STDCPP_INC_BASE="$GCC_TOOLCHAIN/include/c++"
	if [ -d "$STDCPP_INC_BASE" ]; then
		flags_libs="$flags_libs -isystem $STDCPP_INC_BASE"
		flags_p2pool="$flags_p2pool -isystem $STDCPP_INC_BASE"
		TRIPLE_DIR="$(basename "$(dirname "$GCC_TOOLCHAIN")")"
		if [ -n "$TRIPLE_DIR" ] && [ -d "$STDCPP_INC_BASE/$TRIPLE_DIR" ]; then
			flags_libs="$flags_libs -isystem $STDCPP_INC_BASE/$TRIPLE_DIR"
			flags_p2pool="$flags_p2pool -isystem $STDCPP_INC_BASE/$TRIPLE_DIR"
		fi
	fi
fi

cd /p2pool
git apply --verbose --ignore-whitespace --directory=external/src/grpc/third_party/boringssl-with-bazel "$PATCH_DIR/boringssl/win7.patch"
git apply --verbose --ignore-whitespace --directory=external/src/grpc/third_party/boringssl-with-bazel "$PATCH_DIR/boringssl/mingw-clang-intrin.patch"

cd /p2pool/external/src/curl
cmake . -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=../../../cmake/windows_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_libs" -DBUILD_CURL_EXE=OFF -DBUILD_SHARED_LIBS=OFF -DCURL_DISABLE_INSTALL=ON -DCURL_ENABLE_EXPORT_TARGET=OFF -DCURL_DISABLE_HEADERS_API=ON -DCURL_DISABLE_BINDLOCAL=ON -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF -DENABLE_CURL_MANUAL=OFF -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DCURL_DISABLE_ALTSVC=ON -DCURL_DISABLE_COOKIES=ON -DCURL_DISABLE_DOH=ON -DCURL_DISABLE_GETOPTIONS=ON -DCURL_DISABLE_HSTS=ON -DCURL_DISABLE_LIBCURL_OPTION=ON -DCURL_DISABLE_MIME=ON -DCURL_DISABLE_NETRC=ON -DCURL_DISABLE_NTLM=ON -DCURL_DISABLE_PARSEDATE=ON -DCURL_DISABLE_PROGRESS_METER=ON -DCURL_DISABLE_SHUFFLE_DNS=ON -DCURL_DISABLE_SOCKETPAIR=ON -DCURL_DISABLE_VERBOSE_STRINGS=ON -DCURL_DISABLE_WEBSOCKETS=ON -DHTTP_ONLY=ON -DCURL_ENABLE_SSL=OFF -DUSE_LIBIDN2=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DENABLE_UNIX_SOCKETS=OFF -DBUILD_TESTING=OFF -DUSE_NGHTTP2=OFF -DBUILD_EXAMPLES=OFF -DP2POOL_BORINGSSL=ON -DCURL_DISABLE_SRP=ON -DCURL_DISABLE_AWS=ON -DCURL_DISABLE_BASIC_AUTH=ON -DCURL_DISABLE_BEARER_AUTH=ON -DCURL_DISABLE_KERBEROS_AUTH=ON -DCURL_DISABLE_NEGOTIATE_AUTH=ON -DOPENSSL_INCLUDE_DIR=../grpc/third_party/boringssl-with-bazel/include
make -j$(nproc)

cd /p2pool/external/src/libuv
rm -rf build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=../../../../cmake/windows_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_libs" -DBUILD_TESTING=OFF -DLIBUV_BUILD_SHARED=OFF
make -j$(nproc)

cd /p2pool/external/src/libzmq
rm -rf build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=../../../../cmake/windows_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_libs" -DCMAKE_CXX_FLAGS="$flags_libs" -DWITH_LIBSODIUM=OFF -DWITH_LIBBSD=OFF -DBUILD_TESTS=OFF -DWITH_DOCS=OFF -DENABLE_DRAFTS=OFF -DBUILD_SHARED=OFF -DPOLLER=epoll
make -j$(nproc)

cd /p2pool
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM="3.5" -DCMAKE_TOOLCHAIN_FILE=../cmake/windows_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_p2pool" -DCMAKE_CXX_FLAGS="$flags_p2pool" -DOPENSSL_NO_ASM=ON -DSTATIC_BINARY=ON -DARCH_ID=x86_64 -DGIT_COMMIT="$(git rev-parse --short=7 HEAD)"
if ! cmake --build . --target p2pool -- -j$(nproc); then
	cmake --build . --target p2pool-salvium -- -j$(nproc)
	mv p2pool-salvium.exe p2pool.exe
fi

mkdir $1

mv p2pool.exe $1
mv ../LICENSE $1
mv ../README.md $1

chmod -R 0664 $1
chmod 0775 $1
chmod 0775 $1/p2pool.exe

touch -t $TOUCH_DATE $1
touch -t $TOUCH_DATE $1/*
7z a -tzip -mx9 -mfb256 -mpass15 -stl $1.zip $1
