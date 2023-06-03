#!/bin/bash

NGINX_VERSION=1.25.0
OPENSSL_VERSION=3.1.1
GOST_ENGINE_VERSION=3.0.1
OPENSSL_DIR="/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl"

# Update and install required packages
apt-get update
apt-get install -y wget git build-essential libpcre++-dev libz-dev ca-certificates cmake

# Download and extract Nginx source
mkdir -p /usr/local/src
cd /usr/local/src
wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O "nginx-${NGINX_VERSION}.tar.gz"
tar -zxvf "nginx-${NGINX_VERSION}.tar.gz"
rm -f "nginx-${NGINX_VERSION}.tar.gz"

# Download and extract OpenSSL source
wget "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" -O "${OPENSSL_VERSION}.tar.gz"
tar -zxvf "${OPENSSL_VERSION}.tar.gz"
rm -f "${OPENSSL_VERSION}.tar.gz"

cd "nginx-${NGINX_VERSION}"

# Configure and build Nginx with OpenSSL
sed -i 's|--prefix=$ngx_prefix no-shared|--prefix=$ngx_prefix|' auto/lib/openssl/make
./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=www-data \
    --group=www-data \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-openssl="/usr/local/src/openssl-${OPENSSL_VERSION}"
make -j
make install

# Add OpenSSL library path and update ldconfig
echo "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/lib" >> /etc/ld.so.conf.d/ssl.conf
ldconfig 2>/dev/null || /sbin/ldconfig

# Copy OpenSSL binary to /usr/bin
cp "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/bin/openssl" /usr/bin/openssl

# Create cache directory for Nginx
mkdir -p /var/cache/nginx/

# Build GOST-engine for OpenSSL
cd /usr/local/src
git clone --depth 1 --branch "v${GOST_ENGINE_VERSION}" https://github.com/gost-engine/engine "engine-${GOST_ENGINE_VERSION}"
cd "engine-${GOST_ENGINE_VERSION}"
git submodule update --init
mkdir build
cd build
cmake -DCMAKE_BUILD_TYPE=Release \
    -DOPENSSL_ROOT_DIR="${OPENSSL_DIR}" \
    -DOPENSSL_INCLUDE_DIR="${OPENSSL_DIR}/include" \
    -DOPENSSL_LIBRARIES="${OPENSSL_DIR}/lib" \
    -DOPENSSL_ENGINES_DIR="${OPENSSL_DIR}/lib/engines-3" ..
make -j
make install
cp ./bin/gost.so "${OPENSSL_DIR}/lib/engines-3"
cp -r "${OPENSSL_DIR}/lib/engines-3" /usr/lib/x86_64-linux-gnu/
rm -rf "/usr/local/src/engine-${GOST_ENGINE_VERSION}"

# Configure OpenSSL
OPENSSL_CONF="/etc/ssl/openssl.cnf"
sed -i 's|openssl_conf = default_conf|openssl_conf = openssl_def|' "${OPENSSL_CONF}"
echo "" >> "${OPENSSL_CONF}"
echo "# OpenSSL default section" >> "${OPENSSL_CONF}"
echo "[openssl_def]" >> "${OPENSSL_CONF}"
echo "engines = engine_section" >> "${OPENSSL_CONF}"
echo "" >> "${OPENSSL_CONF}"
echo "# Engine section" >> "${OPENSSL_CONF}"
echo "[engine_section]" >> "${OPENSSL_CONF}"
echo "gost = gost_section" >> "${OPENSSL_CONF}"
echo "" >> "${OPENSSL_CONF}"
echo "# Engine gost section" >> "${OPENSSL_CONF}"
echo "[gost_section]" >> "${OPENSSL_CONF}"
echo "engine_id = gost" >> "${OPENSSL_CONF}"
echo "dynamic_path = ${OPENSSL_DIR}/lib/engines-3/gost.so" >> "${OPENSSL_CONF}"
echo "default_algorithms = ALL" >> "${OPENSSL_CONF}"

# Create symlink for OpenSSL library
ln -s "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/lib" "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/lib64"

# Create log file symlinks
ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stderr /var/log/nginx/error.log

# Expose ports
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT

# Start Nginx
nginx -g "daemon off;"

exec bash
