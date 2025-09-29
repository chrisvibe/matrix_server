# Matrix Server

Self-hosted Matrix server with Element web client, using Docker Compose, Nginx, and Cloudflare for SSL.

Inspired by [this guide](https://medium.com/@sncr28/deploying-a-matrix-server-with-element-chat-in-docker-compose-with-nginx-reverse-proxy-cc9850fd32f8).

## Installation

### 1. Configure environment variables

Copy the environment template and fill in your values:

```bash
cp env_template .env
```

Edit `.env` and set your configuration values (domain name, passwords, etc.).

### 2. Generate initial Synapse configuration

```bash
docker compose --env-file .env run --rm \
  -v synapse_data:/data \
  synapse generate
```

### 3. Configure PostgreSQL database

Edit the homeserver configuration:

```bash
docker run --rm -it -v synapse_data:/data alpine sh -c "cd /data && vi homeserver.yaml"
```

Replace the database section with:

```yaml
database:
  name: psycopg2
  args:
    user: synapse
    password: ${POSTGRES_PASSWORD}
    database: synapse
    host: db
    cp_min: 5
    cp_max: 10
```

Optionally, add token-based registration at the bottom:

```yaml
enable_registration: true
enable_registration_without_verification: true
registration_requires_token: true
```

**Optional but recommended:** Add media retention to prevent disk bloat. Add this at the bottom:

```yaml
# Media retention - delete cached remote media after 90 days
# Your own uploads are never deleted
media_retention:
  remote_media_lifetime: 90d
```

Note: By default, Synapse keeps all media forever. This setting only affects cached copies of media from other servers - the originals remain on the server where they were uploaded.

**Optional but recommended:** Add media retention to prevent disk bloat. Add this at the bottom:

```yaml
# Make users discoverable in the user directory by default
user_directory:
  enabled: true
  search_all_users: true  # Allow searching all users, not just room members
  prefer_local_users: true  # Prioritize local users in search results

# Publish user presence/profile by default
presence:
  enabled: true

encryption_enabled_by_default_for_room_type: all
```

### 4. Generate Nginx and Element configurations

```bash
cd nginx
./generate_nginx_config.sh
./generate_ssl_cert.sh  # For federation support
cd ../element
./generate_element_config.sh
cd ..
```

### 5. Set up Cloudflare Tunnel

Cloudflare handles SSL certificates automatically.

1. Create a Cloudflare account and purchase/add your domain
2. Go to **Zero Trust** → **Networks** → **Tunnels**
3. Create a new tunnel with the docker option and copy the tunnel token
4. Add the token to your `.env` file as `CLOUDFLARE_TUNNEL_TOKEN`
5. Configure **three public hostnames** in the tunnel:

   **For federation (server-to-server communication):**
   - **Hostname**: `your-domain.com`
   - **Path**: `_matrix/federation*`
   - **Service**: `https://matrix-nginx:8448`
   - **Additional Settings → TLS → No TLS Verify**: Enable (required for self-signed cert)

   **For federation key exchange:**
   - **Hostname**: `your-domain.com`
   - **Path**: `_matrix/key*`
   - **Service**: `https://matrix-nginx:8448`
   - **Additional Settings → TLS → No TLS Verify**: Enable (required for self-signed cert)

   **For everything else (Element UI, Client API, Admin API, .well-known):**
   - **Hostname**: `your-domain.com`
   - **Path**: `*` (catch-all - must be last in the list)
   - **Service**: `http://matrix-nginx:80`

**Important for Federation**: The federation routes must be separate from client routes. The `_matrix/federation*` and `_matrix/key*` paths handle server-to-server communication on port 8448, while client APIs (`/_matrix/client/*`) must go through port 80. Without proper federation routes, you can only chat with users on your own server.

**Route Order Matters**: Cloudflare processes routes in order. Make sure the catch-all `*` route is last, otherwise it will intercept the federation routes.

### 6. Start the services

```bash
docker compose up -d
```

### 7. Register admin user

Wait for setup to complete (check logs):

```bash
docker compose logs -f synapse
```

Then register your admin account:

```bash
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008
```

### 8. Access your Matrix server

Visit `your-domain.com/matrix` and log in!

### 9. Test Federation (Optional)

To verify federation is working, visit the [Matrix Federation Tester](https://federationtester.matrix.org/) and enter your domain name. It should show all green checks if federation is configured correctly.

You can also test by:
- Joining a public room on another server (e.g., `#matrix:matrix.org`)
- Searching for users from other servers in Element

## User Management

Use the admin tools in the `admin_tools/` folder:

### Generate Registration Tokens

```bash
cd admin_tools
./matrix_admin.sh interactive
```

### Backup and Restore

#### Automated Backup

```bash
# Run backup (creates backups/ directory in project root)
./admin_tools/backup.sh

# Custom backup location and retention
BACKUP_DIR=/path/to/backups KEEP_DAYS=60 ./admin_tools/backup.sh
```

The script:
- Backs up Synapse data, database, and `.env` file
- Automatically cleans backups older than 30 days (configurable)
- Creates timestamped backups: `synapse_data_20250929_143022.tar.gz`

#### Restore from Backup

```bash
# List available backups and restore
./admin_tools/restore.sh

# Or specify backup date directly
./admin_tools/restore.sh 20250929_143022
```

**Warning:** Restore will replace all current data. Stop services first with `docker compose down`.

#### Manual Backup

If you prefer manual backups:

```bash
# Backup Synapse data
docker run --rm -v synapse_data:/data -v $(pwd):/backup alpine tar czf /backup/synapse_data_backup.tar.gz -C /data .

# Backup database
docker compose exec db pg_dump -U synapse synapse | gzip > synapse_db_backup.sql.gz
```

#### Automated Scheduled Backups

Add to crontab for automatic daily backups at 3 AM:

```bash
crontab -e

# Add this line:
0 3 * * * /path/to/matrix_server/admin_tools/backup.sh >> /var/log/matrix_backup.log 2>&1
```
