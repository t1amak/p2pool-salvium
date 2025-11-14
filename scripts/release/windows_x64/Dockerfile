FROM p2pool_build_ubuntu
ARG P2POOL_VERSION
ARG P2POOL_CHECKOUT
ENV P2POOL_CHECKOUT=${P2POOL_CHECKOUT}
ADD . /p2pool/
RUN /p2pool/scripts/release/windows_x64/p2pool_windows_x64.sh p2pool-${P2POOL_VERSION}-windows-x64 ${P2POOL_VERSION}
