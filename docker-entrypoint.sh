#!/bin/bash
# ============================================================
# docker-entrypoint.sh
# Writes Docker environment variables into R's Renviron.site
# so R processes spawned by shiny-server (running as the shiny
# user) can read them via Sys.getenv().
# ============================================================
set -e

cat > /usr/local/lib/R/etc/Renviron.site << EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_KEY=${SUPABASE_KEY}
SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY}
GOOGLE_API_KEY=${GOOGLE_API_KEY}
EOF

exec /usr/bin/shiny-server "$@"
