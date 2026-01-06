# Multi-stage build for Stellar Dark Pool Matching Engine

# Stage 1: Build dependencies
FROM python:3.11-slim as builder

WORKDIR /app

# Install dependencies in a virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy only requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /app

# Install dependencies for Stellar CLI
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install Stellar CLI
RUN curl -L https://github.com/stellar/stellar-cli/releases/download/v21.5.0/stellar-cli-21.5.0-x86_64-unknown-linux-gnu.tar.gz -o stellar.tar.gz && \
    tar -xzf stellar.tar.gz && \
    mv stellar /usr/local/bin/stellar && \
    chmod +x /usr/local/bin/stellar && \
    rm stellar.tar.gz

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application source code (excluding tests via .dockerignore)
COPY src/ ./src/

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create non-root user for security
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    chown -R appuser:appuser /app && \
    mkdir -p /home/appuser/.stellar && \
    chown -R appuser:appuser /home/appuser/.stellar

# Switch to non-root user
USER appuser

# Expose the default REST API port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request, os; port = os.getenv('REST_PORT', '8080'); urllib.request.urlopen(f'http://localhost:{port}/health').read()" || exit 1

# Set entrypoint to generate keys and run the matching engine
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["python", "-m", "src.main"]
