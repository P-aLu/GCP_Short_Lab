#!/bin/bash
# Compute instance startup script — rendered by Terraform templatefile().
# All $${...} placeholders are substituted at plan/apply time; none are shell variables.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y mysql-client

echo "[startup] Waiting for Cloud SQL to accept connections..."
until mysql -h "${sql_ip}" -u "${sql_user}" -p"${sql_password}" \
    -e "SELECT 1" "${db_name}" 2>/dev/null; do
  echo "[startup] Not ready yet — retrying in 15 s..."
  sleep 15
done

echo "[startup] Connected. Creating schema..."

mysql -h "${sql_ip}" -u "${sql_user}" -p"${sql_password}" "${db_name}" -e "
CREATE TABLE IF NOT EXISTS \`Web APIs\` (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(255)  NOT NULL,
  api_user     VARCHAR(255)  NOT NULL,
  api_password VARCHAR(255)  NOT NULL,
  url          VARCHAR(1000) NOT NULL,
  notes        TEXT
);
"

mysql -h "${sql_ip}" -u "${sql_user}" -p"${sql_password}" "${db_name}" -e "
DELETE FROM \`Web APIs\`;
INSERT INTO \`Web APIs\` (name, api_user, api_password, url, notes) VALUES (
  'Internal Metrics API',
  '${cf_api_user}',
  '${cf_api_password}',
  '${cf_url}',
  'Production Cloud Function endpoint — do not share credentials'
);
"

echo "[startup] Schema ready."
