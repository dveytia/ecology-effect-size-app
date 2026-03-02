# ============================================================
# Dockerfile — Ecology Effect Size Coding Platform
# Base image: rocker/shiny 4.3.3 (Debian Bookworm + R 4.3.3)
# ============================================================

FROM rocker/shiny:4.3.3

LABEL maintainer="dveytia"
LABEL org.opencontainers.image.title="Ecology Effect Size Coding Platform"
LABEL org.opencontainers.image.description="Multi-user Shiny app for systematic reviewers to extract and standardise effect sizes."

# ── System libraries ─────────────────────────────────────────────────────────
# libssl/libcurl: httr2  |  libxml2: xml2 (googledrive dep)
# libgdal/geos/proj/udunits2: sf (optional map export)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libudunits2-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ── Install pak (faster parallel package installer) ──────────────────────────
RUN R -e "install.packages('pak', repos = 'https://r-lib.github.io/p/pak/stable/')"

# ── Core R packages (required at runtime) ────────────────────────────────────
RUN R -e "pak::pak(c( \
    'shiny@>=1.8.0', \
    'bslib@>=0.7.0', \
    'shinyjs@>=2.1.0', \
    'httr2@>=1.0.0', \
    'jsonlite@>=1.8.0', \
    'stringr@>=1.5.0', \
    'stringdist@>=0.9.0', \
    'readr@>=2.1.0', \
    'data.table@>=1.14.0', \
    'writexl@>=1.4.0', \
    'tools', \
    'shinycssloaders@>=1.0.0', \
    'shinytoastr@>=0.2.0' \
))"

# ── Optional R packages (map export) ─────────────────────────────────────────
# Failures here do not break the build; map export will simply be unavailable.
RUN R -e "tryCatch( \
    pak::pak(c('ggplot2@>=3.4.0', 'maps', 'sf', 'osmdata')), \
    error = function(e) message('WARNING: optional map packages failed — ', conditionMessage(e)) \
)"

# ── Copy application source ───────────────────────────────────────────────────
WORKDIR /srv/shiny-server/ecology-effect-size-app
COPY . .

# Remove any local secrets that must never be baked into the image
RUN rm -f .Renviron

# ── Custom shiny-server config ────────────────────────────────────────────────
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

# ── Permissions ───────────────────────────────────────────────────────────────
RUN chown -R shiny:shiny /srv/shiny-server /var/log/shiny-server

# ── Expose Shiny port ─────────────────────────────────────────────────────────
EXPOSE 3838

CMD ["/usr/bin/shiny-server"]
