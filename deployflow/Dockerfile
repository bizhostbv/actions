# Tool image for GitLab (and anywhere else the deployflow script has to run in a container).
# Build and publish it under the same tag as the release of this repo:
#   docker build -f deployflow/Dockerfile --build-arg YQ_SHA256=<sha256 of the yq binary> -t <registry>/base/deployflow:<tag> .
# TODO: pin the base by digest, i.e. FROM quay.io/buildah/stable:<tag>@sha256:<digest>
FROM quay.io/buildah/stable:latest

# mikefarah yq (the Fedora "yq" package is a different tool); checksum is mandatory.
ARG YQ_VERSION=v4.53.3
ARG YQ_SHA256
RUN dnf install -y --setopt=install_weak_deps=False skopeo helm jq curl git ca-certificates \
 && dnf clean all \
 && test -n "$YQ_SHA256" \
 && curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" \
 && echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c - \
 && chmod +x /usr/local/bin/yq

# vfs + chroot: buildah inside a container without a fuse/overlay setup
ENV STORAGE_DRIVER=vfs BUILDAH_ISOLATION=chroot
COPY deployflow/bin/deployflow /usr/local/bin/deployflow
