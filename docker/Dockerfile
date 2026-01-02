# SignalOps Production Dockerfile
# Multi-stage build for optimized image size

# Build stage
FROM rocker/shiny:4.3.2 AS builder

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libmariadb-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libsodium-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# Install R packages
RUN install2.r --error --skipinstalled \
    shiny \
    bslib \
    DBI \
    pool \
    RMariaDB \
    dplyr \
    dbplyr \
    ggplot2 \
    plotly \
    DT \
    sodium \
    config \
    httr2 \
    jsonlite \
    lubridate \
    purrr \
    tibble \
    tidyr \
    readr \
    stringr \
    glue \
    memoise \
    cachem \
    logger \
    uuid \
    shinyjs \
    shinyWidgets \
    waiter \
    htmltools \
    promises \
    future \
    rmarkdown \
    knitr \
    digest

# Production stage
FROM rocker/shiny:4.3.2

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libmariadb3 \
    libssl3 \
    libcurl4 \
    libxml2 \
    libsodium23 \
    libfontconfig1 \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /srv/shiny-server/signalops

# Copy application files
COPY app/ .

# Create logs directory
RUN mkdir -p logs && chown -R shiny:shiny /srv/shiny-server/signalops

# Set environment
ENV R_CONFIG_ACTIVE=production
ENV SHINY_LOG_LEVEL=INFO

# Expose port
EXPOSE 3838

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3838/ || exit 1

# Run as shiny user
USER shiny

# Start Shiny server
CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/signalops', host='0.0.0.0', port=3838)"]
