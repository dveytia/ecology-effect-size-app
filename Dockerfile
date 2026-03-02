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
# No version suffixes — pak installs the latest CRAN release, which always
# satisfies the minimums declared in DESCRIPTION. 'tools' is a base package
# and must not be listed here.
RUN R -e "pak::pak(c( \
    'shiny', \
    'bslib', \
    'shinyjs', \
    'httr2', \
    'jsonlite', \
    'stringr', \
    'stringdist', \
    'readr', \
    'data.table', \
    'writexl', \
    'shinycssloaders', \
    'shinytoastr' \
))"

# ── Optional R packages (map export) ─────────────────────────────────────────
# Failures here do not break the build; map export will simply be unavailable.
RUN R -e "tryCatch( \
    pak::pak(c('ggplot2', 'maps', 'sf', 'osmdata')), \
    error = function(e) message('WARNING: optional map packages failed — ', conditionMessage(e)) \
)"

# ── Copy application source ───────────────────────────────────────────────────
WORKDIR /srv/shiny-server/ecology-effect-size-app
COPY . .

# Remove any local secrets that must never be baked into the image
RUN rm -f .Renviron

# ── Custom shiny-server config ────────────────────────────────────────────────
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

# ── Entrypoint: write env vars to Renviron.site before starting server ───────
# shiny-server spawns R processes as the 'shiny' user which doesn't inherit
# the container environment. Writing to /etc/R/Renviron.site makes vars
# available to all R processes regardless of which user runs them.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN sed -i 's/\r//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

# ── Permissions ───────────────────────────────────────────────────────────────
RUN chown -R shiny:shiny /srv/shiny-server /var/log/shiny-server

# ── Expose Shiny port ─────────────────────────────────────────────────────────
EXPOSE 3838

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
