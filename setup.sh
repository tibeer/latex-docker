#!/usr/bin/env bash

set -eo pipefail

scheme="$1"

retry() {
  retries=$1
  shift

  count=0
  until "$@"; do
    exit=$?
    wait="$(echo "2^$count" | bc)"
    count="$(echo "$count + 1" | bc)"
    if [ "$count" -lt "$retries" ]; then
      echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
      sleep "$wait"
    else
      echo "Retry $count/$retries exited $exit, no more retries left."
      return "$exit"
    fi
  done
}

case "$(uname -m)" in
  x86_64)
    echo "binary_x86_64-linux 1" >>/texlive.profile
    TEX_ARCH=x86_64-linux
    ;;

  aarch64)
    echo "binary_aarch64-linux 1" >>/texlive.profile
    TEX_ARCH=aarch64-linux
    ;;

  *)
    echo "Unknown arch: $(uname -m)" >&2
    exit 1
    ;;
esac

echo "==> Install system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends --no-install-suggests \
  curl \
  fontconfig \
  ghostscript \
  git \
  gpg \
  gpg-agent \
  gnuplot-nox \
  graphviz \
  make \
  openjdk-17-jre-headless \
  perl-base \
  python3-minimal \
  python3-pygments \
  tar

# Dependencies needed by latexindent
apt-get install -y --no-install-recommends --no-install-suggests \
  libfile-homedir-perl \
  libunicode-linebreak-perl \
  libyaml-tiny-perl

echo "==> Install TeXLive"
mkdir -p /opt/texlive/
ln -sf "/opt/texlive/texdir/bin/$TEX_ARCH" /opt/texlive/bin
mkdir -p /tmp/install-tl
cd /tmp/install-tl
MIRROR_URL="$(curl -fsS -w "%{redirect_url}" -o /dev/null https://mirror.ctan.org/)"
echo "Use mirror url: ${MIRROR_URL}"
curl -fsSOL "${MIRROR_URL}systems/texlive/tlnet/install-tl-unx.tar.gz"
curl -fsSOL "${MIRROR_URL}systems/texlive/tlnet/install-tl-unx.tar.gz.sha512"
curl -fsSOL "${MIRROR_URL}systems/texlive/tlnet/install-tl-unx.tar.gz.sha512.asc"
gpg --import /texlive_pgp_keys.asc
gpg --verify ./install-tl-unx.tar.gz.sha512.asc ./install-tl-unx.tar.gz.sha512
sha512sum -c ./install-tl-unx.tar.gz.sha512
mkdir -p /tmp/install-tl/installer
tar --strip-components 1 -zxf /tmp/install-tl/install-tl-unx.tar.gz -C /tmp/install-tl/installer
retry 3 /tmp/install-tl/installer/install-tl -scheme "scheme-$scheme" -profile=/texlive.profile

# Install additional packages for non full scheme
if [[ $scheme != "full" ]]; then
  tlmgr install \
    collection-bibtexextra \
    collection-fontsrecommended \
    collection-fontutils \
    latexmk \
    texliveonfly \
    xindy
fi

# System font configuration for XeTeX and LuaTeX
# Ref: https://www.tug.org/texlive/doc/texlive-en/texlive-en.html#x1-330003.4.4
ln -s /opt/texlive/texdir/texmf-var/fonts/conf/texlive-fontconfig.conf /etc/fonts/conf.d/09-texlive.conf
fc-cache -fv

echo "==> Clean up"
apt-get autoremove -y --purge
apt-get clean -y
rm -rf \
  /opt/texlive/texdir/install-tl \
  /opt/texlive/texdir/install-tl.log \
  /opt/texlive/texdir/texmf-dist/doc \
  /opt/texlive/texdir/texmf-dist/source \
  /opt/texlive/texdir/texmf-var/web2c/tlmgr.log \
  /setup.sh \
  /texlive.profile \
  /texlive_pgp_keys.asc \
  /tmp/install-tl
