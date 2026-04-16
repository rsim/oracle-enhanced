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

# Download and install Oracle Instant Client based on architecture
WORKDIR /tmp
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        ARCH_SUFFIX="arm64"; \
        IC_VERSION="23.26.0.0.0"; \
        IC_PATH="2326000"; \
    else \
        ARCH_SUFFIX="x64"; \
        IC_VERSION="23.26.1.0.0"; \
        IC_PATH="2326100"; \
    fi && \
    wget -q https://download.oracle.com/otn_software/linux/instantclient/${IC_PATH}/instantclient-basic-linux.${ARCH_SUFFIX}-${IC_VERSION}.zip \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/${IC_PATH}/instantclient-sdk-linux.${ARCH_SUFFIX}-${IC_VERSION}.zip \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/${IC_PATH}/instantclient-sqlplus-linux.${ARCH_SUFFIX}-${IC_VERSION}.zip \
    && unzip -qo instantclient-basic-linux.${ARCH_SUFFIX}-${IC_VERSION}.zip \
    && unzip -qo instantclient-sdk-linux.${ARCH_SUFFIX}-${IC_VERSION}.zip \
    && unzip -qo instantclient-sqlplus-linux.${ARCH_SUFFIX}-${IC_VERSION}.zip \
    && mv instantclient_23_26 /opt/oracle/instantclient \
    && rm -f instantclient-*.zip

# Set Oracle environment variables
ENV ORACLE_HOME=/opt/oracle/instantclient \
    LD_LIBRARY_PATH=/opt/oracle/instantclient:$LD_LIBRARY_PATH \
    PATH=/opt/oracle/instantclient:$PATH

# Switch to vscode user
USER vscode

# Set working directory
WORKDIR /workspaces/oracle-enhanced
