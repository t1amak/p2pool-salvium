#!/bin/sh
set -e

cd /p2pool
git fetch --jobs=$(nproc)
git checkout $2
git submodule update --recursive --jobs $(nproc)

export TZ=UTC0

BUILD_TIMESTAMP=$(git show --no-patch --format=%ct $2)
CURRENT_DATE=$(date -u -d @$BUILD_TIMESTAMP +"%Y-%m-%d")
CURRENT_TIME=$(date -u -d @$BUILD_TIMESTAMP +"%H:%M:%S")
TOUCH_DATE=$(date -u -d @$BUILD_TIMESTAMP +"%Y%m%d%H%M.%S")

flags_size=""
flags_datetime="-D__DATE__=\"\\\"$CURRENT_DATE\\\"\" -D__TIME__=\"\\\"$CURRENT_TIME\\\"\" -Wno-builtin-macro-redefined"

flags_libs="-Os -flto -w $flags_size $flags_datetime"
flags_p2pool="$flags_size $flags_datetime"

clang_bin="$(command -v x86_64-apple-darwin25-clang || true)"
clangxx_bin="$(command -v x86_64-apple-darwin25-clang++ || true)"
clangas_bin="$(command -v x86_64-apple-darwin25-as || true)"
if [ -z "$clang_bin" ] || [ -z "$clangxx_bin" ] || [ -z "$clangas_bin" ]; then
	echo "macOS cross toolchain binaries not found in PATH" >&2
	exit 1
fi

find_macos_sdk() {
	if [ -n "${SDKROOT:-}" ] && [ -d "${SDKROOT:-}" ]; then
		echo "$SDKROOT"
		return 0
	fi

	for base in /usr/local/target/SDK /usr/local/osxcross/target/SDK /osxcross/target/SDK; do
		if [ -d "$base" ]; then
			for candidate in "$base"/MacOSX*.sdk; do
				if [ -d "$candidate" ]; then
					echo "$candidate"
					return 0
				fi
			done
		fi
	done

	find /usr/local -maxdepth 4 -name 'MacOSX*.sdk' -type d 2>/dev/null | head -n 1
}

sdk_sysroot="$(find_macos_sdk)"
if [ -z "$sdk_sysroot" ]; then
	echo "Unable to locate macOS SDK sysroot. Set SDKROOT to the SDK path." >&2
	exit 1
fi

export SDKROOT="$sdk_sysroot"
cmake_osx_args="-DCMAKE_OSX_SYSROOT=$sdk_sysroot -DCMAKE_SYSROOT=$sdk_sysroot -DCMAKE_SYSTEM_FRAMEWORK_PATH=$sdk_sysroot/System/Library/Frameworks"

wrap_compiler() {
	real_bin="$1"
	wrapper_path="$2"
	cat > "$wrapper_path" <<EOF
#!/bin/sh
set -e
for arg in "\$@"; do
	case "\$arg" in
		-print-sysroot|--print-sysroot)
			if [ -n "\$SDKROOT" ]; then
				printf '%s\n' "\$SDKROOT"
				exit 0
			fi
			;;
	esac
done
exec "$real_bin" "\$@"
EOF
	chmod +x "$wrapper_path"
}

wrapper_dir="$(mktemp -d)"
trap "rm -rf '$wrapper_dir'" EXIT

cc_wrapper="$wrapper_dir/x86_64-apple-darwin25-clang"
cxx_wrapper="$wrapper_dir/x86_64-apple-darwin25-clang++"
as_wrapper="$wrapper_dir/x86_64-apple-darwin25-as"

wrap_compiler "$clang_bin" "$cc_wrapper"
wrap_compiler "$clangxx_bin" "$cxx_wrapper"
wrap_compiler "$clangas_bin" "$as_wrapper"

cmake_compiler_args="-DCMAKE_C_COMPILER=$cc_wrapper -DCMAKE_CXX_COMPILER=$cxx_wrapper -DCMAKE_ASM_COMPILER=$as_wrapper"

cd /p2pool/external/src/curl
cmake . -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=../../../cmake/macos_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_libs" $cmake_osx_args $cmake_compiler_args -DBUILD_CURL_EXE=OFF -DBUILD_SHARED_LIBS=OFF -DCURL_DISABLE_INSTALL=ON -DCURL_ENABLE_EXPORT_TARGET=OFF -DCURL_DISABLE_HEADERS_API=ON -DCURL_DISABLE_BINDLOCAL=ON -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF -DENABLE_CURL_MANUAL=OFF -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DCURL_DISABLE_ALTSVC=ON -DCURL_DISABLE_COOKIES=ON -DCURL_DISABLE_DOH=ON -DCURL_DISABLE_GETOPTIONS=ON -DCURL_DISABLE_HSTS=ON -DCURL_DISABLE_LIBCURL_OPTION=ON -DCURL_DISABLE_MIME=ON -DCURL_DISABLE_NETRC=ON -DCURL_DISABLE_NTLM=ON -DCURL_DISABLE_PARSEDATE=ON -DCURL_DISABLE_PROGRESS_METER=ON -DCURL_DISABLE_SHUFFLE_DNS=ON -DCURL_DISABLE_SOCKETPAIR=ON -DCURL_DISABLE_VERBOSE_STRINGS=ON -DCURL_DISABLE_WEBSOCKETS=ON -DHTTP_ONLY=ON -DCURL_ENABLE_SSL=OFF -DUSE_LIBIDN2=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DENABLE_UNIX_SOCKETS=OFF -DBUILD_TESTING=OFF -DUSE_NGHTTP2=OFF -DBUILD_EXAMPLES=OFF -DP2POOL_BORINGSSL=ON -DCURL_DISABLE_SRP=ON -DCURL_DISABLE_AWS=ON -DCURL_DISABLE_BASIC_AUTH=ON -DCURL_DISABLE_BEARER_AUTH=ON -DCURL_DISABLE_KERBEROS_AUTH=ON -DCURL_DISABLE_NEGOTIATE_AUTH=ON -DOPENSSL_INCLUDE_DIR=../grpc/third_party/boringssl-with-bazel/include
make -j$(nproc)

cd /p2pool/external/src/libuv
rm -rf build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=../../../../cmake/macos_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_libs" $cmake_osx_args $cmake_compiler_args -DBUILD_TESTING=OFF -DLIBUV_BUILD_SHARED=OFF
make -j$(nproc)

cd /p2pool/external/src/libzmq
rm -rf build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TOOLCHAIN_FILE=../../../../cmake/macos_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_libs" -DCMAKE_CXX_FLAGS="$flags_libs" $cmake_osx_args $cmake_compiler_args -DWITH_LIBSODIUM=OFF -DWITH_LIBBSD=OFF -DBUILD_TESTS=OFF -DWITH_DOCS=OFF -DENABLE_DRAFTS=OFF -DBUILD_SHARED=OFF
make -j$(nproc)

cd /p2pool
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM="3.5" -DCMAKE_TOOLCHAIN_FILE=../cmake/macos_x86_64_toolchain_clang.cmake -DCMAKE_C_FLAGS="$flags_p2pool" -DCMAKE_CXX_FLAGS="$flags_p2pool" $cmake_osx_args $cmake_compiler_args -DOPENSSL_NO_ASM=ON -DSTATIC_LIBS=ON -DARCH_ID=x86_64 -DGIT_COMMIT="$(git rev-parse --short=7 HEAD)"
if ! cmake --build . --target p2pool -- -j$(nproc); then
	cmake --build . --target p2pool-salvium -- -j$(nproc)
	mv p2pool-salvium p2pool
fi

mkdir $1

mv p2pool $1
mv ../LICENSE $1
mv ../README.md $1

chmod -R 0664 $1
chmod 0775 $1
chmod 0775 $1/p2pool

tar cvf $1.tar --format=pax --pax-option='exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime' --sort=name --owner=0 --group=0 --mtime="$CURRENT_DATE $CURRENT_TIME" $1
touch -t $TOUCH_DATE $1.tar
7z a -tgzip -mx9 -mfb256 -mpass15 -stl $1.tar.gz $1.tar
