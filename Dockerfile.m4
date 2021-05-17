m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/alpine:3]], [[FROM docker.io/alpine:3]]) AS build
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN apk add --no-cache \
		build-base \
		ca-certificates \
		curl \
		lz4-dev \
		lz4-static \
		openssl-dev \
		openssl-libs-static \
		perl \
		zlib-dev \
		zlib-static \
		zstd-dev \
		zstd-static

# Switch to unprivileged user
ENV USER=builder GROUP=builder
RUN addgroup -S "${GROUP:?}"
RUN adduser -S -G "${GROUP:?}" "${USER:?}"
USER "${USER}:${GROUP}"

# Build Busybox
ARG BUSYBOX_VERSION=1.33.1
ARG BUSYBOX_TARBALL_URL=https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2
ARG BUSYBOX_TARBALL_CHECKSUM=12cec6bd2b16d8a9446dd16130f2b92982f1819f6e1c5f5887b6db03f5660d28
RUN mkdir /tmp/busybox/
WORKDIR /tmp/busybox/
RUN curl -Lo /tmp/busybox.tbz2 "${BUSYBOX_TARBALL_URL:?}"
RUN printf '%s' "${BUSYBOX_TARBALL_CHECKSUM:?}  /tmp/busybox.tbz2" | sha256sum -c
RUN tar -xjf /tmp/busybox.tbz2 --strip-components=1 -C /tmp/busybox/
RUN make allnoconfig
RUN setcfg() { sed -ri "s/^(# )?(${1:?})( is not set|=.*)$/\2=${2?}/" ./.config; } \
	&& setcfg CONFIG_STATIC                y \
	&& setcfg CONFIG_LFS                   y \
	&& setcfg CONFIG_BUSYBOX               y \
	&& setcfg CONFIG_FEATURE_SH_STANDALONE y \
	&& setcfg CONFIG_SH_IS_[A-Z0-9_]+      n \
	&& setcfg CONFIG_SH_IS_ASH             y \
	&& setcfg CONFIG_BASH_IS_[A-Z0-9_]+    n \
	&& setcfg CONFIG_BASH_IS_NONE          y \
	&& setcfg CONFIG_ASH                   y \
	&& setcfg CONFIG_ASH_[A-Z0-9_]+        n \
	&& setcfg CONFIG_ASH_PRINTF            y \
	&& setcfg CONFIG_ASH_TEST              y \
	&& setcfg CONFIG_AWK                   y \
	&& setcfg CONFIG_CAT                   y \
	&& setcfg CONFIG_CHMOD                 y \
	&& setcfg CONFIG_CHOWN                 y \
	&& setcfg CONFIG_ID                    y \
	&& setcfg CONFIG_MKDIR                 y \
	&& setcfg CONFIG_MKPASSWD              y \
	&& grep -v '^#' ./.config | sort | uniq
RUN make -j "$(nproc)" && make install
RUN test -z "$(readelf -x .interp ./_install/bin/busybox 2>/dev/null)"
RUN strip -s ./_install/bin/busybox

# Build Dropbear
ARG DROPBEAR_VERSION=2020.81
ARG DROPBEAR_TARBALL_URL=https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VERSION}.tar.bz2
ARG DROPBEAR_TARBALL_CHECKSUM=48235d10b37775dbda59341ac0c4b239b82ad6318c31568b985730c788aac53b
RUN mkdir /tmp/dropbear/
WORKDIR /tmp/dropbear/
RUN curl -Lo /tmp/dropbear.tbz2 "${DROPBEAR_TARBALL_URL:?}"
RUN printf '%s' "${DROPBEAR_TARBALL_CHECKSUM:?}  /tmp/dropbear.tbz2" | sha256sum -c
RUN tar -xjf /tmp/dropbear.tbz2 --strip-components=1 -C /tmp/dropbear/
RUN ./configure --enable-static --disable-wtmp --disable-lastlog CFLAGS='-DSFTPSERVER_PATH=\"/bin/sftp-server\"'
RUN make -j "$(nproc)" PROGRAMS='dropbear dropbearkey scp' MULTI=1 SCPPROGRESS=1
RUN test -z "$(readelf -x .interp ./dropbearmulti 2>/dev/null)"
RUN strip -s ./dropbearmulti

# Build OpenSSH SFTP-server
ARG OPENSSH_VERSION=8.5p1
ARG OPENSSH_TARBALL_URL=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz
ARG OPENSSH_TARBALL_CHECKSUM=f52f3f41d429aa9918e38cf200af225ccdd8e66f052da572870c89737646ec25
RUN mkdir /tmp/openssh/
WORKDIR /tmp/openssh/
RUN curl -Lo /tmp/openssh.tgz "${OPENSSH_TARBALL_URL:?}"
RUN printf '%s' "${OPENSSH_TARBALL_CHECKSUM:?}  /tmp/openssh.tgz" | sha256sum -c
RUN tar -xzf /tmp/openssh.tgz --strip-components=1 -C /tmp/openssh/
RUN ./configure CFLAGS='-static' LDFLAGS='-static'
RUN make -j "$(nproc)" ./sftp-server
RUN test -z "$(readelf -x .interp ./sftp-server 2>/dev/null)"
RUN strip -s ./sftp-server

# Build rsync
ARG RSYNC_VERSION=3.2.3
ARG RSYNC_TARBALL_URL=https://download.samba.org/pub/rsync/src/rsync-${RSYNC_VERSION}.tar.gz
ARG RSYNC_TARBALL_CHECKSUM=becc3c504ceea499f4167a260040ccf4d9f2ef9499ad5683c179a697146ce50e
RUN mkdir /tmp/rsync/
WORKDIR /tmp/rsync/
RUN curl -Lo /tmp/rsync.tgz "${RSYNC_TARBALL_URL:?}"
RUN printf '%s' "${RSYNC_TARBALL_CHECKSUM:?}  /tmp/rsync.tgz" | sha256sum -c
RUN tar -xzf /tmp/rsync.tgz --strip-components=1 -C /tmp/rsync/
RUN ./configure CFLAGS='-static' LDFLAGS='-static' --disable-xxhash
RUN make -j "$(nproc)"
RUN test -z "$(readelf -x .interp ./rsync 2>/dev/null)"
RUN strip -s ./rsync

# Create rootfs
USER root:root
RUN mkdir /tmp/rootfs/
WORKDIR /tmp/rootfs/
RUN install -D /tmp/busybox/_install/bin/busybox ./bin/busybox
RUN install -D /tmp/dropbear/dropbearmulti ./bin/dropbearmulti
RUN install -D /tmp/openssh/sftp-server ./bin/sftp-server
RUN install -D /tmp/rsync/rsync ./bin/rsync
WORKDIR /tmp/rootfs/bin/
RUN ln -s ./dropbearmulti ./dropbear
RUN ln -s ./dropbearmulti ./dropbearkey
RUN ln -s ./dropbearmulti ./scp
WORKDIR /tmp/rootfs/
RUN mkdir -p ./etc/dropbear/ ./home/
RUN touch ./etc/group ./etc/passwd ./etc/shadow
COPY ./scripts/bin/ ./bin/
RUN find ./ -type d -exec chmod 755 '{}' ';'
RUN find ./ -type f -exec chmod 644 '{}' ';'
RUN find ./bin/ -type f -exec chmod 755 '{}' ';'
RUN chmod 775 ./etc/dropbear/ ./home/
RUN chmod 664 ./etc/group ./etc/passwd ./etc/shadow
RUN chown -R root:root ./

##################################################
## "dropbear" stage
##################################################

FROM scratch AS dropbear

COPY --from=build /tmp/rootfs/ /

USER 0:0
ENTRYPOINT ["/bin/init"]
CMD ["-F", "-E", "-m", "-w", "-j", "-k", "-p", "0.0.0.0:2222"]
