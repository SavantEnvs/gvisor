# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — gvisor (Go, native f.Fuzz -> go-118-fuzz-build + clang libFuzzer).
# Builds on the org C/C++ base (clang links the go-fuzz archive), adds a pinned Go
# toolchain + go-118-fuzz-build under /opt/toolchains, then runs mayhem/build.sh.
FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS

# Pinned Go (version + tarball sha256) and go-118-fuzz-build pseudo-version, plus the
# pinned upstream go-branch commit build.sh materializes. gvisor go.mod requires go >= 1.26.3.
ARG GO_VERSION=1.26.5
ARG GO_SHA256=5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053
ARG GO118FB_VERSION=v0.0.0-20250520111509-a70c2aa677fa

ENV GOROOT=/opt/toolchains/go \
    GOPATH=/opt/toolchains/go-path \
    GOMODCACHE=/opt/toolchains/go-path/pkg/mod \
    GOCACHE=/opt/toolchains/go-path/build-cache \
    GOTOOLCHAIN=local \
    GOFLAGS=-mod=mod \
    PATH=/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:${PATH} \
    GVISOR_GO_SRC=/opt/toolchains/src/gvisor \
    GVISOR_GO_COMMIT=2354a1a30e978a3e28fc69e64e7880f7a886ba23 \
    GO118FB_TESTING_VERSION=v0.0.0-20250520111509-a70c2aa677fa

USER root
RUN install -d /opt/toolchains/go-path /opt/toolchains/src \
 && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
 && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
 && tar -C /opt/toolchains -xzf /tmp/go.tgz && rm -f /tmp/go.tgz \
 # go-118-fuzz-build (native f.Fuzz -> libFuzzer archive). Installing it seeds its
 # module (incl. the /testing shim + go-fuzz-headers) into GOMODCACHE for offline re-runs.
 && go install "github.com/AdamKorcz/go-118-fuzz-build@${GO118FB_VERSION}" \
 && chown -R 2000:2000 /opt/toolchains/go-path /opt/toolchains/src

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
