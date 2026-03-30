#!/bin/bash

set -e
set -x

# =========================
# Basic variables
# =========================
CURDIR=$(dirname $(readlink -f "$0"))
TOPDIR=$(git rev-parse --show-toplevel 2>/dev/null)

DEBDIR="${TOPDIR}/contrib/packages/deb/ubuntu-jammy"

VERSION=$(grep '^set(VERSION ' "${TOPDIR}/CMakeLists.txt" | sed 's@^set(VERSION \(.*\))@\1@')

# =========================
# Prepare the build directory
# =========================
rm -rf "${CURDIR}/build"
mkdir -p "${CURDIR}/build"
chmod a+w "${CURDIR}/build"
[ -x /usr/sbin/selinuxenabled ] && /usr/sbin/selinuxenabled && chcon -Rt container_file_t "${CURDIR}/build"

# =========================
# Copy over the source code
# =========================
(cd "${TOPDIR}" && git archive --prefix OsConnect-${VERSION}/ HEAD) | xz > "${CURDIR}/build/OsConnect_${VERSION}.orig.tar.xz"

# =========================
# Copy over the packaging files
# =========================
cp -r "${DEBDIR}/debian" "${CURDIR}/build/debian"
chmod a+x "${CURDIR}/build/debian/rules"

# =========================
# Assemble a fake changelog entry to get the correct version
# =========================
cat - > "${CURDIR}/build/debian/changelog" << EOT
OsConnect (${VERSION}-1ubuntu1) UNRELEASED; urgency=low

  * Automated build for OsConnect

 -- Build bot <OsConnectbot@OsConnect.org>  $(date -R)

EOT

cat "${DEBDIR}/debian/changelog" >> "${CURDIR}/build/debian/changelog"

# =========================
# Start the build inside Docker
# =========================
docker run --volume "${CURDIR}/build:/home/deb/build" --interactive --rm OsConnect/${DOCKER} \
    bash -e -x -c "
    set -e
    # Extract source
    tar -C ~/build -axf ~/build/OsConnect_${VERSION}.orig.tar.xz
    # Copy debian files
    cp -a ~/build/debian ~/build/OsConnect-${VERSION}/debian
    # Update apt
    sudo apt-get update
    # Create build-deps
    mk-build-deps ~/build/OsConnect-${VERSION}/debian/control
    # Install build dependencies safely (wildcard expanded)
    DEB_FILE=(~/OsConnect-build-deps_*.deb)
    if [ \${#DEB_FILE[@]} -eq 0 ]; then
        echo 'No DEB build-deps found!'
        exit 1
    fi
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \"\${DEB_FILE[@]}\"
    # Build the package
    cd ~/build/OsConnect-${VERSION} && dpkg-buildpackage -us -uc
    "

# =========================
# Copy resulting packages
# =========================
mkdir -p "${CURDIR}/result"
cp -av "${CURDIR}/build/"*.deb "${CURDIR}/result/"
cp -av "${CURDIR}/build/"*.ddeb "${CURDIR}/result/"

echo "✅ OsConnect DEB packages are ready in ${CURDIR}/result"