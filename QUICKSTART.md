# Quick-Start Guide

Get the Ecological Effect Size Coding Platform running on your computer in about 30 minutes.

---

## What You Will Need

| Tool | Where to get it |
|------|-----------------|
| **R** (version 4.3 or newer) | https://cloud.r-project.org |
| **RStudio Desktop** | https://posit.co/download/rstudio-desktop |
| **Git** | https://git-scm.com/downloads |
| **Docker Desktop** *(optional, for container run)* | https://www.docker.com/products/docker-desktop |
| A free **Supabase** account | https://supabase.com |
| *(Optional)* A **Google Cloud** account | https://console.cloud.google.com |

Google Cloud is only needed if you want the PDF-viewing feature (linking articles to PDFs stored in a shared Google Drive folder). Everything else works without it.

---

## 1 — Create a Supabase Project

Supabase is a free cloud database and authentication service. It stores all your project data, articles, and user accounts.

1. Go to **https://supabase.com** and sign up (GitHub or email).
2. Click **New project**.
3. Fill in:
   - **Organisation:** your name or team
   - **Project name:** anything you like (e.g. `ecology-app`)
   - **Database password:** choose a strong password and **save it somewhere safe**
   - **Region:** pick the one closest to you
4. Click **Create new project** and wait about two minutes.

### Copy your API credentials

1. In the Supabase sidebar, click **⚙ Project Settings → API**.
2. Note down three values — you will paste them into a file in Step 4:

| Value | Where it appears | Looks like |
|-------|-----------------|------------|
| **Project URL** | Top of the API page | `https://abcdefghij.supabase.co` |
| **anon public key** | Under "Project API keys" | `eyJhbGciO…` (long string) |
| **service_role key** | Under "Project API keys" (click **Reveal**) | `eyJhbGciO…` (another long string) |

> Keep the service_role key private — it has full database access.

### Disable email confirmation (recommended)

By default Supabase requires new users to confirm their email via a link. The confirmation link redirects to the **Site URL** configured in your Supabase project, which defaults to `http://localhost:3000` — a page that doesn't exist for this app. The account is still created and usable, but the broken redirect is confusing.

**Simplest fix — turn off email confirmation:**

1. In the Supabase sidebar, go to **Authentication → Providers → Email**.
2. Uncheck **"Confirm email"**.
3. Click **Save**.

New users will be logged in immediately after registering — no confirmation email needed. This is the recommended setting for small research teams with known collaborators.

**Alternative — fix the redirect URL:**

If you prefer to keep email confirmation enabled, update the redirect so the link works:

1. Go to **Authentication → URL Configuration**.
2. Set **Site URL** to your app's address (e.g. `http://localhost:3838` for local dev, or your deployed URL).

---

## 2 — Run the Database Setup Scripts

These SQL scripts create all the tables, policies, and triggers the app needs.

1. In Supabase, click **SQL Editor** in the left sidebar.
2. For **each** of the following files (in this order), click **+ New query**, paste the file contents, then click **Run**:

| Order | File | What it does |
|-------|------|-------------|
| 1 | `sql/01_create_tables.sql` | Creates all tables |
| 2 | `sql/02_rls_policies.sql` | Row-level security (multi-user access control) |
| 3 | `sql/03_triggers.sql` | Auto-create user profile on sign-up |
| 4 | `sql/04_indexes.sql` | Performance indexes |
| 5 | `sql/05_duplicate_flags.sql` | Duplicate detection queue |
| 6 | `sql/06_phase5_rls_patch.sql` | Security patch for uploads |
| 7 | `sql/07_gdrive_columns.sql` | Google Drive and article numbering columns |
| 8 | `sql/08_effect_type_column.sql` | Effect type tracking column |
| 9 | `sql/09_effect_sizes_delete_policy.sql` | Allow effect size row deletion |
| 10 | `sql/10_sequence_grants.sql` | Permission for auto-numbering |
| 11 | `sql/11_fix_projects_rls.sql` | Fix project creation permissions |
| 12 | `sql/12_reviewer_presence.sql` | Live reviewer presence in the Review tab |

Each script should print a green "Success" message. If any script fails, check for typos — scripts must be run in order because later ones depend on earlier ones.

### Verify the tables

Click **Table Editor** in the Supabase sidebar. You should see tables including:
`users`, `projects`, `project_members`, `labels`, `articles`, `uploads`, `article_metadata_json`, `effect_sizes`, `audit_log`, `duplicate_flags`.

### Verify RLS policies

Click **Authentication -> Policies** in the side bar and verify the following tables match:

`article_metadata_json`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|amj_insert|INSERT|public|
|amj_select|SELECT|public|
|amj_update|UPDATE|public|

`articles`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|articles_delete|DELETE|authenticated|
|articles_insert|INSERT|public|
|articles_select|SELECT|public|
|articles_update|UPDATE|public|

`audit_log`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|auditlog_insert|INSERT|public|
|auditlog_select|SELECT|public|

`duplicate_flags`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|dup_flags_delete|DELETE|authenticated|
|dup_flags_insert|INSERT|authenticated|
|dup_flags_select|SELECT|authenticated|
|dup_flags_update|UPDATE|authenticated|

`effect_sizes`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|es_delete|DELETE|authenticated|
|es_insert|INSERT|public|
|es_select|SELECT|public|
|es_update|UPDATE|public|

`labels`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|labels_delete|DELETE|public|
|labels_insert|INSERT|public|
|labels_select|SELECT|public|
|labels_update|UPDATE|public|

`project_members`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|pm_delete|DELETE|public|
|pm_insert|INSERT|public|
|pm_select|SELECT|public|

`projects`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|allow_all_delete|DELETE|authenticated|
|allow_all_insert|INSERT|authenticated|
|allow_all_select|SELECT|authenticated|
|projects_update|UPDATE|authenticated|

`uploads`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|uploads_delete|DELETE|autenticated|
|uploads_insert|INSERT|public|
|uploads_select|SELECT|public|
|uploads_update|UPDATE|authenticated|

`users`
|NAME|COMMAND|APPLIED TO|
|----|-------|----------|
|users_insert|INSERT|public|
|users_select|SELECT|public|
|users_update|UPDATE|public|
---

## 3 — Clone the Repository

Open **RStudio**. In the top menu, click:

**File → New Project → Version Control → Git**

- **Repository URL:** `https://github.com/dveytia/ecology-effect-size-app`
- **Project directory name:** `ecology-effect-size-app`
- **Create project as subdirectory of:** choose a folder (e.g. `Documents`)

Click **Create Project**. RStudio will download the code and open the project.

---

## 4 — Create Your `.Renviron` File

The `.Renviron` file stores your private credentials. It is never uploaded to GitHub.

1. In the RStudio **Files** panel (bottom-right), click `.Renviron.example` to open it.
2. **File → Save As…** and save it as `.Renviron` (filename starts with a dot, no `.example` at the end).
3. Replace the placeholder values with your real Supabase credentials from Step 1:

```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_KEY=your-anon-public-key
SUPABASE_SERVICE_KEY=your-service-role-key
```

4. Save the file.
5. Restart R so the credentials are loaded: **Session → Restart R**.

> **Google Drive setup is optional** — see [Section 10](#10--optional-set-up-google-drive-pdf-viewing) below. You can skip it for now and add it later.

---

## 5 — Install R Packages

If you prefer to run the app in Docker instead of local R/RStudio, skip to **Step 5B**.

### 5A — Local R/RStudio (default)

This project uses `renv` for reproducible package versions.

Before restoring packages, check your R version:

```r
R.version.string
```

The lockfile in this repo was created with **R 4.5.0**. Restoring with an older R can fail for some dependencies.

In the RStudio **Console**, paste and run:

```r
install.packages("renv")
renv::consent(provided = TRUE)

# Beginner-safe path: install only packages needed to run the app UI.
runtime_pkgs <- c(
   "shiny", "bslib", "shinyjs", "httr2", "jsonlite", "stringr", "stringdist",
   "readr", "data.table", "writexl", "shinycssloaders", "shinytoastr"
)
renv::restore(packages = runtime_pkgs, prompt = FALSE)
```

This usually takes a few minutes on first install.

If you want the full developer/test stack later, run:

```r
renv::restore(prompt = FALSE)
```

If `renv::restore()` fails:

1. Update R to 4.5.x and restart RStudio.
2. Update renv and try again:

```r
install.packages("renv")
renv::restore(packages = runtime_pkgs, prompt = FALSE)
```

3. If your internet/proxy is unstable, retry once after setting CRAN explicitly:

```r
options(repos = c(CRAN = "https://cloud.r-project.org"))
renv::restore(packages = runtime_pkgs, prompt = FALSE)
```

### If You Need To Create a New `renv.lock` (maintainers)

Only do this when creating a new project lockfile or intentionally updating dependencies.

```r
install.packages("renv")
renv::init(bare = TRUE)
renv::settings$package.dependency.fields(c("Imports", "Depends", "LinkingTo", "Suggests"))
renv::install(c(
   "shiny", "bslib", "shinyjs", "httr2", "jsonlite", "stringr", "stringdist",
   "readr", "data.table", "writexl", "shinycssloaders", "shinytoastr",
   "testthat", "googledrive", "ggplot2", "maps", "sf", "osmdata"
))
renv::snapshot(
   packages = c(
      "shiny", "bslib", "shinyjs", "httr2", "jsonlite", "stringr", "stringdist",
      "readr", "data.table", "writexl", "shinycssloaders", "shinytoastr",
      "testthat", "googledrive", "ggplot2", "maps", "sf", "osmdata"
   ),
   prompt = FALSE,
   force = TRUE
)
```

Commit these files after snapshotting:
- `renv.lock`
- `renv/settings.json`
- `renv/activate.R`
- `.Rprofile`

### 5B — Docker image (alternative)

Use this path if you want the app and package environment fully containerised.

1. In the project root, copy `.env.example` to `.env`.
2. Open `.env` and set at least:

```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_KEY=your-anon-public-key
SUPABASE_SERVICE_KEY=your-service-role-key
APP_IMAGE_TAG=dev-local
```

3. *(Optional)* Set `GOOGLE_API_KEY` in `.env` for Drive sync.
4. Build and start the container:

```bash
docker compose build
docker compose up -d
```

5. Open the app at `http://localhost:3838/ecology-effect-size-app`.
6. View logs if needed:

```bash
docker compose logs -f shiny
```

7. Stop the app:

```bash
docker compose down
```

Notes:
- Docker reads credentials from `.env` (not `.Renviron`).
- If you update dependencies and `renv.lock`, rebuild the image: `docker compose build --no-cache`.

---

## 6 — Launch the App

In the RStudio Console, run:

```r
shiny::runApp()
```

A browser window will open showing the **Ecology Effect Size Coder** login page.

---

## 7 — Register and Create Your First Project

### Register an account

1. On the login page, click the **Register** tab.
2. Enter your email and a password (minimum 8 characters), then click **Create Account**.
3. You will be logged in automatically and taken to the **Dashboard**.

### Create a project

1. Click **+ New Project**.
2. Enter a title and description.
3. *(Optional)* If you have an existing project you want to copy labels from, select it in the "Clone labels from" dropdown. Only the label structure is copied — no articles or data.
4. Click **Create**.

Your project appears under **Projects I Own**. Click it to open.

---

## 8 — Upload Articles

### Prepare your file

Your article file should be a **CSV** (comma-separated) or **TXT/TSV** (tab-delimited) file with UTF-8 encoding. Tab-delimited is recommended when titles or abstracts contain commas.

**Required columns:**

| Column | Description |
|--------|-------------|
| `title` | Article title |
| `abstract` | Full abstract text |
| `author` | Author names (any format) |
| `year` | Publication year (integer) |
| `doi` | DOI (with or without `https://doi.org/` prefix) |

**Optional column:**

| Column | Description |
|--------|-------------|
| `article_num` | Integer ID for the article. When supplied, Drive PDFs named `[article_num].pdf` will be linked automatically during Google Drive sync. If omitted, numbers are assigned automatically. |

### Upload

1. In your project, click the **Upload** tab.
2. Click **Browse…** and select your file.
3. The app will parse the file and show a preview with clean rows and any detected duplicates.
4. Click **Upload** to insert the articles.

Clean rows are inserted immediately. If any duplicates are detected, they appear in the **Upload History** tab where you can accept or reject each one.

You can upload multiple files — each upload is recorded as a separate batch.

---

## 9 — Invite Collaborators

Collaborators must register their own account first (share the app URL with them).

### From the Dashboard

1. On your project card, click the **Invite** button (person-plus icon).
2. Enter their registered email address and click **Send Invitation**.

### From within a project

1. Open the project, click the **Members** tab.
2. Click **+ Invite Member** and enter their email.

Invited users see the project under **Projects I've Joined** on their Dashboard. They can review articles and code effect sizes but cannot modify labels or project settings — only the project owner can do that.

To remove a collaborator, go to the **Members** tab and click the red remove button next to their name.

---

## 10 — *(Optional)* Set Up Google Drive PDF Viewing

This lets the app display article PDFs from a shared Google Drive folder directly alongside the review form.

### One-time Google Cloud setup

1. Go to **https://console.cloud.google.com**.
2. Create a project (or select an existing one).
3. Enable the **Google Drive API**:
   - Navigate to **APIs & Services → Library**.
   - Search for "Google Drive API" and click **Enable**.
4. Create an API key:
   - Navigate to **APIs & Services → Credentials**.
   - Click **+ CREATE CREDENTIALS → API key**.
   - Copy the key (starts with `AIza…`).
5. Add the key to your `.Renviron` file:

```
GOOGLE_API_KEY=AIza...your-key-here
```

6. Restart R: **Session → Restart R**.

### Prepare your Drive folder

1. In Google Drive, create a folder for your project's PDFs.
2. Name each PDF file as `[article_num].pdf` — for example, `1.pdf`, `2.pdf`, `42.pdf`. The number must match the `article_num` column in your uploaded articles.
3. Right-click the folder → **Share → General access → "Anyone with the link"** (set to **Viewer**). This is required because the app uses a public API key, not individual sign-in.
4. Copy the folder URL (e.g. `https://drive.google.com/drive/folders/abc123...`).

### Link the folder to your project

1. In the app, open your project from the Dashboard.
2. On the project card, click **Edit** (pencil icon).
3. Paste the Drive folder URL into the **Google Drive Folder URL** field.
4. Click **Sync Now** — the app will scan the folder and link matching PDFs to your articles.
5. Click **Save Changes**.

After syncing, PDFs will appear in the Review tab when you open an article that has a linked file.

---

## 11 — Share the Docker Image with Another User or Server

There are two common ways to send this app image to someone:

1. Push to a container registry (best for teams and updates)
2. Export a `.tar` image file (best for offline transfer)

### Before sharing: keep `.env` private

- Never commit `.env` to git.
- This repo already protects secrets:
   - `.env` is ignored by `.gitignore`
   - `.env` is excluded from Docker build context by `.dockerignore`
- Share `.env.example` with collaborators and have them create their own `.env`.

Quick checks before publishing:

```bash
git status --short
git check-ignore -v .env
```

The second command should show `.gitignore` as the ignore source.

### Option A — Publish to a Registry

#### A1. Docker Hub example

On your machine:

```bash
# Set your values
export DOCKERHUB_USER="yourdockerhubuser"
export IMAGE="ecology-effect-size-app"
export VERSION="2026-04-08"

# Build and tag
docker build -t ${DOCKERHUB_USER}/${IMAGE}:${VERSION} .
docker tag ${DOCKERHUB_USER}/${IMAGE}:${VERSION} ${DOCKERHUB_USER}/${IMAGE}:latest

# Login and push
docker login
docker push ${DOCKERHUB_USER}/${IMAGE}:${VERSION}
docker push ${DOCKERHUB_USER}/${IMAGE}:latest
```

On the new server:

```bash
export DOCKERHUB_USER="yourdockerhubuser"
export IMAGE="ecology-effect-size-app"
export VERSION="2026-04-08"

# Pull exact version
docker pull ${DOCKERHUB_USER}/${IMAGE}:${VERSION}

# Create env file from template and edit secrets
cp .env.example .env

# Run with explicit env file
docker run -d \
   --name ecology-effect-size-app \
   --env-file .env \
   -p 3838:3838 \
   ${DOCKERHUB_USER}/${IMAGE}:${VERSION}
```

#### A2. GHCR example (GitHub Container Registry)

On your machine:

```bash
# Set your values
export GH_USER="dveytia"
export REPO="ecology-effect-size-app"
export VERSION="2026-04-21"
export IMAGE="ghcr.io/${GH_USER}/${REPO}"

# Build with OCI labels so GHCR can associate package metadata
# SOURCE should be your GitHub repository URL
docker build \
   --label org.opencontainers.image.source="https://github.com/${GH_USER}/${REPO}" \
   --label org.opencontainers.image.version="${VERSION}" \
   -t ${IMAGE}:${VERSION} \
   -t ${IMAGE}:latest \
   .

# Login to GHCR (GitHub PAT needs: write:packages, read:packages) 
# (only need to run this the first time and then credentials are stored)
echo "YOUR_GITHUB_PAT" | docker login ghcr.io -u ${GH_USER} --password-stdin


# Push both version and latest tags
docker push ${IMAGE}:${VERSION}
docker push ${IMAGE}:latest
```

On the new server:

```bash
export GH_USER="your-github-username"
export REPO="ecology-effect-size-app"
export VERSION="2026-04-08"
export IMAGE="ghcr.io/${GH_USER}/${REPO}"

# If package is private, login first
echo "YOUR_GITHUB_PAT" | docker login ghcr.io -u ${GH_USER} --password-stdin

# Pull exact version
docker pull ${IMAGE}:${VERSION}

# Create env file from template and edit secrets
cp .env.example .env

# Run with explicit env file
docker run -d \
   --name ecology-effect-size-app \
   --env-file .env \
   -p 3838:3838 \
   ${IMAGE}:${VERSION}
```

GHCR notes on versions and repository association:

- Each tag (for example `2026-04-08`, `latest`) is published as a package version.
- To associate a GHCR container with a repository, use the label:
   - `org.opencontainers.image.source=https://github.com/OWNER/REPO`
- After first push, open GitHub: **Repository -> Packages -> package -> Package settings**:
   - Confirm linked repository
   - Set visibility (private/public)
   - Grant access permissions if needed

If using Compose on the new server:

```bash
docker compose --env-file .env pull
docker compose --env-file .env up -d
```

### Option B — Send a `.tar` Image File (Offline)

On your machine:

```bash
# 1) Build and tag
docker build -t ecology-effect-size-app:2026-04-08 .

# 2) Export image to a tar file
docker save -o ecology-effect-size-app_2026-04-08.tar ecology-effect-size-app:2026-04-08
```

Transfer `ecology-effect-size-app_2026-04-08.tar` to the target server (USB, SCP, cloud drive, etc.).

On the new server:

```bash
# 1) Import image
docker load -i ecology-effect-size-app_2026-04-08.tar

# 2) Create env file from template and edit secrets
cp .env.example .env

# 3) Run with explicit env file
docker run -d \
   --name ecology-effect-size-app \
   --env-file .env \
   -p 3838:3838 \
   ecology-effect-size-app:2026-04-08
```

### Optional hardening for shared servers

```bash
# Restrict file permissions so only owner can read .env
chmod 600 .env
```

---

## Using the App Day-to-Day

### Review articles

1. Open a project and click the **Review** tab.
2. Select an article from the sidebar list on the left.
3. Fill in the label fields (these are defined by the project owner in the **Labels** tab).
4. Click **Save** to record your responses, or **Next** to save and advance to the next unreviewed article. Use **Skip** to mark an article as skipped without saving.

### Code effect sizes

If the project includes an `effect_size` label, a dedicated effect size form appears below the label fields. Select the study design (control/treatment, correlation, regression, interaction, or time trend) and fill in the relevant statistics. The app computes standardised Pearson *r* and Fisher *Z* automatically.

### Export data

1. Click the **Export** tab.
2. Use the filters to narrow down which articles to include.
3. **Full Export** downloads a CSV with all article metadata, label responses, and effect sizes.
4. **Meta-Ready Export** downloads a CSV formatted for the `metafor` R package (columns `yi` and `vi` for meta-analysis).

### Audit log

The **Audit Log** tab shows a timestamped record of every save, skip, and edit. Click the diff button on any entry to compare before-and-after snapshots side by side.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| App says `SUPABASE_URL is not set` | Save your `.Renviron` file and restart R (**Session → Restart R**) |
| `401 Unauthorized` on login | Double-check your `SUPABASE_KEY` and `SUPABASE_SERVICE_KEY` — no extra spaces |
| Tables not found | Re-run the SQL scripts in order (Step 2) |
| Google Drive sync shows 0 files | Make sure the folder is shared as "Anyone with the link can view" and that `GOOGLE_API_KEY` is set in `.Renviron` |
| PDFs not linking to articles | PDF filenames must be `[article_num].pdf` (e.g. `42.pdf`). Check that the number matches the `article_num` in your articles table |
| Invite says "No account found" | The collaborator needs to register their own account first using the app's Register tab |
| Upload says complete but articles don't appear | Run `sql/10_sequence_grants.sql` in Supabase SQL Editor if you haven't already |

---

## Project Structure at a Glance

```
ecology-effect-size-app/
├── app.R              ← App entry point
├── ui.R / server.R    ← Top-level UI and server
├── global.R           ← Package loading
├── R/                 ← Backend logic (auth, database, effect sizes, export, Drive)
├── modules/           ← Shiny UI modules (one per tab/feature)
├── sql/               ← Database setup scripts (run in Supabase)
├── tests/             ← Automated tests (for developers)
├── www/               ← CSS and JavaScript assets
├── .Renviron.example  ← Template for your credentials file
└── QUICKSTART.md      ← This file
```
