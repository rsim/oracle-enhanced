FROM mcr.microsoft.com/devcontainers/ruby:1-3.4-bookworm

# Install libaio1 (required for Oracle Instant Client)
RUN apt-get update && apt-get install -y libaio1 \
    && rm -rf /var/lib/apt/lists/*

# Create directory structure for Oracle
RUN mkdir -p /opt/oracle

# Download and install Oracle Instant Client based on architecture
WORKDIR /tmp
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        ARCH_SUFFIX="arm64"; \
    else \
        ARCH_SUFFIX="x64"; \
    fi && \
    wget -q https://download.oracle.com/otn_software/linux/instantclient/2380000/instantclient-basic-linux.${ARCH_SUFFIX}-23.8.0.25.04.zip \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/2380000/instantclient-sdk-linux.${ARCH_SUFFIX}-23.8.0.25.04.zip \
    && wget -q https://download.oracle.com/otn_software/linux/instantclient/2380000/instantclient-sqlplus-linux.${ARCH_SUFFIX}-23.8.0.25.04.zip \
    && unzip -qo instantclient-basic-linux.${ARCH_SUFFIX}-23.8.0.25.04.zip \
    && unzip -qo instantclient-sdk-linux.${ARCH_SUFFIX}-23.8.0.25.04.zip \
    && unzip -qo instantclient-sqlplus-linux.${ARCH_SUFFIX}-23.8.0.25.04.zip \
    && mv instantclient_23_8 /opt/oracle/instantclient \
    && rm -f instantclient-*.zip

# Set Oracle environment variables
ENV ORACLE_HOME=/opt/oracle/instantclient \
    LD_LIBRARY_PATH=/opt/oracle/instantclient:$LD_LIBRARY_PATH \
    PATH=/opt/oracle/instantclient:$PATH

# Switch to vscode user
USER vscode

# Set working directory
WORKDIR /workspaces/oracle-enhanced
