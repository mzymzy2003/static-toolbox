#!/bin/bash
#set -e
set -o pipefail
set -x
NMAP_COMMIT=

fetch(){
    if [ ! -d "/build/musl" ];then
        #git clone https://github.com/GregorR/musl-cross.git /build/musl
        git clone https://github.com/takeshixx/musl-cross.git /build/musl
    fi
    if [ ! -d "/build/openssl" ];then
        git clone https://github.com/drwetter/openssl-pm-snapshot.git /build/openssl
    fi
    if [ ! -d "/build/nmap" ];then
        git clone https://github.com/nmap/nmap.git /build/nmap
    fi
    NMAP_COMMIT=$(cd /build/nmap/ && git rev-parse --short HEAD)
}

build_musl_aarch64() {
    cd /build/musl
    git clean -fdx
    echo "ARCH=arm64" >> config.sh
    echo "GCC_BUILTIN_PREREQS=yes" >> config.sh
    echo "TRIPLE=aarch64-linux-musleabi" >> config.sh
    ./build.sh
    echo "[+] Finished building musl-cross aarch64"
}

build_openssl_aarch64() {
    cd /build/openssl
    git clean -fdx
    make clean
    CC='/opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-gcc -static' ./Configure no-shared linux-generic64
    make -j4
    echo "[+] Finished building OpenSSL aarch64"
}

build_nmap_aarch64() {
    cd /build/nmap
    git clean -fdx
    make clean
    cd /build/nmap/libz
    CC='/opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-gcc -static -fPIC' \
        CXX='/opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-g++ -static -static-libstdc++ -fPIC' \
        cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_LINKER=/opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-ld .
    make zlibstatic
    cd /build/nmap
    CC='/opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-gcc -static -fPIC' \
        CXX='/opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-g++ -static -static-libstdc++ -fPIC' \
        CXXFLAGS="-I/build/nmap/libz" \
        LD=/opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-ld \
        LDFLAGS="-L/build/openssl -L/build/nmap/libz" \
        ./configure \
            --host=aarch64-none-linux-gnueabi \
            --without-ndiff \
            --without-zenmap \
            --without-nmap-update \
            --without-libssh2 \
            --with-pcap=linux \
            --with-libz=/build/nmap/libz \
            --with-openssl=/build/openssl \
            --with-liblua=included
    sed -i -e 's/shared\: /shared\: #/' libpcap/Makefile
    sed -i 's|LIBS = |& libz/libz.a |' Makefile
    make -j4
    if [ ! -f "/build/nmap/nmap" -o ! -f "/build/nmap/ncat/ncat" -o ! -f "/build/nmap/nping/nping" ];then
        echo "[-] Building Nmap armhf failed!"
        exit 1
    fi
    if [ -f "/build/nmap/nmap" -a -f "/build/nmap/ncat/ncat" -a -f "/build/nmap/nping/nping" ];then
        /opt/cross/aarch64-linux-musleabi/bin/aarch64-linux-musleabi-strip nmap ncat/ncat nping/nping
    fi
}

build_aarch64(){
    OUT_DIR_AARCH64=/output/`uname | tr 'A-Z' 'a-z'`/aarch64
    mkdir -p $OUT_DIR_AARCH64
    build_musl_aarch64
    build_openssl_aarch64
    build_nmap_aarch64
    if [ ! -f "/build/nmap/nmap" -o ! -f "/build/nmap/ncat/ncat" -o ! -f "/build/nmap/nping/nping" ];then
        echo "[-] Building Nmap aarch64 failed!"
        exit 1
    fi
    cp /build/nmap/nmap "${OUT_DIR_AARCH64}/nmap-${NMAP_COMMIT}"
    cp /build/nmap/ncat/ncat "${OUT_DIR_AARCH64}/ncat-${NMAP_COMMIT}"
    cp /build/nmap/nping/nping "${OUT_DIR_AARCH64}/nping-${NMAP_COMMIT}"
    echo "[+] Finished building Nmap aarch64"
}

main() {
    if [ ! -d "/output" ];then
        echo "[-] /output does not exist, creating it"
        mkdir /output
    fi
    fetch
    build_aarch64
}

main
