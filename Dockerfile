# ============================================================
# Dockerfile — Ecology Effect Size Coding Platform
# Base image pinned by digest for reproducibility
# ============================================================

FROM rocker/shiny:4.5.0@sha256:b7e4848fc56fb567287459b40e5ce75b50c5fdc930c34ae86634f751ca79fd1e

LABEL maintainer="dveytia"
LABEL org.opencontainers.image.title="Ecology Effect Size Coding Platform"
LABEL org.opencontainers.image.description="Multi-user Shiny app for systematic reviewers to extract and standardise effect sizes."

# ── System libraries ─────────────────────────────────────────────────────────
# libssl/libcurl: httr2  |  libxml2: xml2/xslt (googledrive deps)
# libgdal/geos/proj/udunits2/absl: sf + s2 (optional map export)
# graphics/text libs: rsvg, magick, textshaping (test/docs transitive deps)
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libxslt1-dev \
    libgdal-dev \
    gdal-bin \
    libgeos-dev \
    libproj-dev \
    libudunits2-dev \
    libabsl-dev \
    libprotobuf-dev \
    protobuf-compiler \
    librsvg2-dev \
    libmagick++-dev \
    libsodium-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ── Reproducible R dependency restore (renv lockfile) ───────────────────────
RUN R -e "install.packages('renv', repos = 'https://cloud.r-project.org')"

WORKDIR /srv/shiny-server/ecology-effect-size-app

# Copy lock metadata first to maximize Docker layer cache reuse.
COPY renv.lock renv.lock
COPY renv/activate.R renv/settings.json renv/

# Install only runtime packages needed by the app from the lockfile.
# This avoids pulling optional/test stacks in Suggests during image build.
RUN R -e "required <- c('shiny','bslib','shinyjs','httr2','jsonlite','stringr','stringdist','readr','data.table','writexl','shinycssloaders','shinytoastr'); renv::consent(provided = TRUE); renv::restore(packages = required, library = .Library.site[[1]], prompt = FALSE); missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]; if (length(missing)) stop(sprintf('Missing required package(s): %s', paste(missing, collapse = ', ')))"

# ── Copy application source ───────────────────────────────────────────────────
COPY . .

# Remove any local secrets that must never be baked into the image
RUN rm -f .Renviron

# Disable project renv autoload inside the container runtime.
# Dependencies are already restored into the shared image library above.
RUN rm -f .Rprofile

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
