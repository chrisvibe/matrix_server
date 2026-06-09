#!/bin/sh
# Matrix backup orchestrator. Unlike parvis (DB-only), matrix has TWO datastores that
# must BOTH be captured for a complete, restorable backup:
#   1. the synapse Postgres DB        -> backup_db.sh   (matrix_db_*.dump)
#   2. the synapse_data volume        -> backup_data.sh (matrix_data_*.tar.gz)
#      (media store, homeserver signing key, local config — none of which live in PG)
# Kept separate from backup-entrypoint.sh so the entrypoint/cron line stays identical
# across every service. set -eu: if the DB dump fails the run aborts (surfaces the error)
# rather than silently producing a half backup.
set -eu

/scripts/backup_db.sh
/scripts/backup_data.sh
