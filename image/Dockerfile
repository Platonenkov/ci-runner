# Ephemeral GitHub Actions runner for the StaticBit-io private repositories. Runs under sysbox-runc, which gives
# the container its own Docker daemon without --privileged, so concurrent jobs never share ports, networks or
# compose projects (glintwild binds 127.0.0.1:6006 and :5180 and asserts that no glintwildit containers remain).
FROM ubuntu:24.04

ARG RUNNER_VERSION
ARG NODE_MAJOR=24

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache \
    DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    ImageOS=ubuntu24

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg lsb-release git git-lfs jq unzip zip xz-utils file rsync openssh-client \
      sudo iproute2 iptables procps util-linux shellcheck python3 python3-pip python3-venv build-essential \
      libicu74 libssl3 tzdata \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
      > /etc/apt/sources.list.d/docker.list \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin gh nodejs \
 && rm -rf /var/lib/apt/lists/*

# Preinstalled so setup-dotnet finds the channel in its default Linux install dir instead of downloading it per job.
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
 && bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
 && bash /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet \
 && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
 && rm /tmp/dotnet-install.sh

# Same uid and passwordless sudo as the hosted runner user, so workflows written for ubuntu-latest behave the same.
RUN useradd -m -u 1001 -s /bin/bash runner \
 && usermod -aG docker runner \
 && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner \
 && chmod 0440 /etc/sudoers.d/runner \
 && mkdir -p /opt/hostedtoolcache \
 && chown -R runner:runner /opt/hostedtoolcache /usr/share/dotnet

# setup-node looks in the tool cache before downloading, and its download comes from GitHub release assets in
# Azure Blob Storage, which some hosting networks reach at a fraction of their bandwidth (a 10-minute stall
# cancelled a job on 2026-11-12). The latest release of each major goes into the cache here, from nodejs.org;
# the weekly image rebuild keeps it current. A workflow asking for another major still downloads it.
ARG NODE_TOOLCACHE_MAJORS="24 22"
RUN for major in ${NODE_TOOLCACHE_MAJORS}; do \
      version="$(curl -fsSL https://nodejs.org/dist/index.json | jq -r --arg m "v${major}." '[.[] | select(.version | startswith($m))][0].version | ltrimstr("v")')" \
   && dir="/opt/hostedtoolcache/node/${version}/x64" \
   && mkdir -p "$dir" \
   && curl -fsSL "https://nodejs.org/dist/v${version}/node-v${version}-linux-x64.tar.xz" | tar -xJ -C "$dir" --strip-components=1 \
   && touch "${dir}.complete" \
   || exit 1; \
    done \
 && chown -R runner:runner /opt/hostedtoolcache

WORKDIR /home/runner/actions-runner
RUN curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && tar xzf runner.tar.gz \
 && rm runner.tar.gz \
 && ./bin/installdependencies.sh \
 && chown -R runner:runner /home/runner

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
