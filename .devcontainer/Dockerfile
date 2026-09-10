FROM mcr.microsoft.com/devcontainers/base:trixie

# Install libaio1t64 and provide a libaio.so.1 symlink for Oracle Instant Client
# Install rlwrap for readline support in sqlplus
RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y libaio1t64 rlwrap \
    && rm -rf /var/lib/apt/lists/* \
    && DEB_HOST_MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" \
    && ln -sf /usr/lib/${DEB_HOST_MULTIARCH}/libaio.so.1t64 \
              /usr/lib/${DEB_HOST_MULTIARCH}/libaio.so.1 \
    && echo "alias sqlplus='rlwrap sqlplus'" >> /etc/bash.bashrc

# Create directory structure for Oracle
RUN mkdir -p /opt/oracle

# Download and install Oracle Instant Client based on architecture.
# x86_64 uses Oracle's version-less "always latest" URLs; arm64 must pin a
# version because Oracle does not publish version-less arm64 zips.
WORKDIR /tmp
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        IC_VERSION="23.26.3.0.0"; \
        IC_PATH="2326300"; \
        BASE_URL="https://download.oracle.com/otn_software/linux/instantclient/${IC_PATH}"; \
        BASIC="instantclient-basic-linux.arm64-${IC_VERSION}.zip"; \
        SDK="instantclient-sdk-linux.arm64-${IC_VERSION}.zip"; \
        SQLPLUS="instantclient-sqlplus-linux.arm64-${IC_VERSION}.zip"; \
    else \
        BASE_URL="https://download.oracle.com/otn_software/linux/instantclient"; \
        BASIC="instantclient-basic-linuxx64.zip"; \
        SDK="instantclient-sdk-linuxx64.zip"; \
        SQLPLUS="instantclient-sqlplus-linuxx64.zip"; \
    fi && \
    wget -q "${BASE_URL}/${BASIC}" \
    && wget -q "${BASE_URL}/${SDK}" \
    && wget -q "${BASE_URL}/${SQLPLUS}" \
    && unzip -qo "${BASIC}" \
    && unzip -qo "${SDK}" \
    && unzip -qo "${SQLPLUS}" \
    && mv instantclient_*/ /opt/oracle/instantclient \
    && rm -f instantclient-*.zip

# Set Oracle environment variables
ENV ORACLE_HOME=/opt/oracle/instantclient \
    LD_LIBRARY_PATH=/opt/oracle/instantclient:$LD_LIBRARY_PATH \
    PATH=/opt/oracle/instantclient:$PATH

# Switch to vscode user
USER vscode

# Set working directory
WORKDIR /workspaces/oracle-enhanced
