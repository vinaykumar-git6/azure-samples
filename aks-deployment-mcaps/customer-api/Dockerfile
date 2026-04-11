# =============================================================================
# Multi-stage Docker build for Customer REST API
# =============================================================================
# Stage 1: Build stage - Install dependencies
# Stage 2: Runtime stage - Lightweight production image
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS builder

# Set working directory
WORKDIR /app

# Install system dependencies required for building Python packages
# - gcc, g++: Required for compiling psycopg2
# - postgresql-dev: PostgreSQL client libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies to /install directory
# Using --prefix to install to custom location for copying to runtime stage
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# -----------------------------------------------------------------------------
# Stage 2: Runtime
# -----------------------------------------------------------------------------
FROM python:3.11-slim

# Set metadata labels (best practice for container images)
LABEL maintainer="your-email@example.com"
LABEL description="Customer REST API with PostgreSQL and Azure AD authentication"
LABEL version="1.0"

# Set environment variables
# PYTHONUNBUFFERED: Ensures Python output is sent straight to terminal (useful for logs)
# PYTHONDONTWRITEBYTECODE: Prevents Python from writing .pyc files
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    FLASK_ENV=production \
    PORT=5000

# Create non-root user for security (best practice)
# Running as root in containers is a security risk
RUN useradd -m -u 1000 appuser && \
    mkdir -p /app && \
    chown -R appuser:appuser /app

# Install runtime dependencies only (minimal image size)
# libpq5: PostgreSQL client library (required for psycopg2)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from builder stage
COPY --from=builder /install /usr/local

# Set working directory
WORKDIR /app

# Copy application code
COPY --chown=appuser:appuser app.py .

# Switch to non-root user
USER appuser

# Expose port (documentation purpose - actual port mapping done at runtime)
EXPOSE 5000

# Health check (best practice for production containers)
# Kubernetes/AKS will use this to determine if container is healthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:5000/health')" || exit 1

# Run the application using waitress (production WSGI server)
# Do NOT use Flask's built-in server in production
CMD ["python", "app.py"]
