#!/bin/bash
set -e

exec 2>> ./errors_gost.log

# Log errors to a file called "errors_gost.log"

export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=UTF-8
export LANG=en_US.UTF-8
#Get rid of the locale warning

readonly NGINX_VERSION=1.25.0
readonly OPENSSL_VERSION=3.1.1
readonly GOST_ENGINE_VERSION=3.0.1
readonly OPENSSL_DIR="/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl"

# Define version numbers and installation directories as read-only variables

function handle_error {
    local message=$1
    local exit_code=${2:-1}
    echo "${message}, error code: ${exit_code}" >> ./errors_gost.log
    exit ${exit_code}
}

# Define a function to handle errors, which logs the error message and code to the error log file

{
    apt update -qq || handle_error "Failed to update packages"
    apt install -y wget git build-essential libpcre++-dev libz-dev ca-certificates cmake ufw || handle_error "Failed to install necessary packages"

    # Update package list and install required packages

    mkdir -p /usr/local/src || handle_error "Failed to create /usr/local/src"
    cd /usr/local/src || handle_error "Failed to change directory to /usr/local/src"

    # Create directory /usr/local/src and change to it

    curl -LO "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" || handle_error "Failed to download NGINX"
    tar -zxvf "nginx-${NGINX_VERSION}.tar.gz" || handle_error "Failed to unzip NGINX"
    rm -f "nginx-${NGINX_VERSION}.tar.gz" || handle_error "Failed to remove NGINX tar.gz"

    # Download NGINX source code, extract it, and remove the tar.gz file

    curl -LO "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" || handle_error "Failed to download OpenSSL"
    tar -zxvf "openssl-${OPENSSL_VERSION}.tar.gz" || handle_error "Failed to unzip OpenSSL"
    rm -f "openssl-${OPENSSL_VERSION}.tar.gz" || handle_error "Failed to remove OpenSSL tar.gz"

    # Download OpenSSL source code, extract it, and remove the tar.gz file

    cd "nginx-${NGINX_VERSION}" || handle_error "Failed to change directory to nginx-${NGINX_VERSION}"

    sed -i.bak 's|--prefix=$ngx_prefix no-shared|--prefix=$ngx_prefix|' auto/lib/openssl/make || handle_error "Failed to replace in file"
    rm auto/lib/openssl/make.bak || handle_error "Failed to remove make.bak"

    # Replace a line in a file to fix a configuration issue

    if ! ./configure \
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
        --with-openssl="/usr/local/src/openssl-${OPENSSL_VERSION}"; then
        handle_error "Failed to configure NGINX"
    fi

    # Configure NGINX with desired options

    make -j || handle_error "Failed to build NGINX"
    make install || handle_error "Failed to install NGINX"

    # Build and install NGINX

    echo "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/lib" >> /etc/ld.so.conf.d/ssl.conf
    ldconfig 2>/dev/null || /sbin/ldconfig

    # Add OpenSSL library path to ldconfig and update the cache

    cp "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/bin/openssl" /usr/bin/openssl || handle_error "Failed to copy OpenSSL"

    # Copy the OpenSSL binary to /usr/bin/openssl

    mkdir -p /var/cache/nginx/

    # Create directory /var/cache/nginx/

    cd /usr/local/src || handle_error "Failed to change directory to /usr/local/src"
    git clone --depth 1 --branch "v${GOST_ENGINE_VERSION}" https://github.com/gost-engine/engine "engine-${GOST_ENGINE_VERSION}" || handle_error "Failed to clone GOST engine repository"
    cd "engine-${GOST_ENGINE_VERSION}" || handle_error "Failed to change directory to engine-${GOST_ENGINE_VERSION}"
    git submodule update --init || handle_error "Failed to update submodules"

    # Clone GOST engine repository and update submodules

    mkdir build || handle_error "Failed to create build directory"
    cd build || handle_error "Failed to change directory to build"
    cmake -DCMAKE_BUILD_TYPE=Release \
        -DOPENSSL_ROOT_DIR="${OPENSSL_DIR}" \
        -DOPENSSL_INCLUDE_DIR="${OPENSSL_DIR}/include" \
        -DOPENSSL_LIBRARIES="${OPENSSL_DIR}/lib" \
        -DOPENSSL_ENGINES_DIR="${OPENSSL_DIR}/lib/engines-3" .. || handle_error "Failed to run CMake"
    make -j || handle_error "Failed to build GOST engine"
    make install || handle_error "Failed to install GOST engine"
    cp ./bin/gost.so "${OPENSSL_DIR}/lib/engines-3" || handle_error "Failed to copy GOST engine"
    cp -r "${OPENSSL_DIR}/lib/engines-3" /usr/lib/x86_64-linux-gnu/ || handle_error "Failed to copy GOST engine"

    # Build and install GOST engine, copy the resulting library to OpenSSL's engines directory

    rm -rf "/usr/local/src/engine-${GOST_ENGINE_VERSION}" || handle_error "Failed to remove GOST engine source directory"

    # Remove the source directory of the GOST engine

    OPENSSL_CONF="/etc/ssl/openssl.cnf"
    sed -i.bak 's|openssl_conf = default_conf|openssl_conf = openssl_def|' "${OPENSSL_CONF}" || handle_error "Failed to replace in OpenSSL config"
    rm "${OPENSSL_CONF}.bak" || handle_error "Failed to remove backup of OpenSSL config"

    # Modify OpenSSL configuration file to include GOST engine settings

    cat << EOF >> "${OPENSSL_CONF}"
# OpenSSL default section
[openssl_def]
engines = engine_section

# Engine section
[engine_section]
gost = gost_section

# Engine gost section
[gost_section]
engine_id = gost
dynamic_path = ${OPENSSL_DIR}/lib/engines-3/gost.so
default_algorithms = ALL
EOF

    # Append GOST engine configuration to OpenSSL configuration file

    ln -s "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/lib" "/usr/local/src/openssl-${OPENSSL_VERSION}/.openssl/lib64"

    # Create a symbolic link to OpenSSL library directory

    ln -sf /dev/stdout /var/log/nginx/access.log
    ln -sf /dev/stderr /var/log/nginx/error.log

    # Create symbolic links for NGINX log files to stdout and stderr

    ufw allow 80/tcp || handle_error "Failed to allow port 80"
    ufw allow 443/tcp || handle_error "Failed to allow port 443"

    # Allow incoming connections on ports 80 (HTTP) and 443 (HTTPS) using UFW

    nginx -g "daemon off;" || handle_error "Failed to start NGINX"

    # Start NGINX in the foreground

    exec bash || handle_error "Failed to execute bash"
} || {
    echo "An error occurred during the installation of NGINX with OpenSSL and GOST engine"
    exit 1
}

# Catch any errors that occurred during the installation process and display an error message
