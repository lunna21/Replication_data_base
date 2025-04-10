#!/bin/bash
set -e

# Este script debe ejecutarse desde dentro del contenedor de una réplica

# Promover la réplica a maestro
pg_ctl promote -D "$PGDATA"

# Verificar que la promoción fue exitosa
until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
  echo "Esperando a que PostgreSQL se inicie como primario..."
  sleep 1
done

echo "Réplica promovida a maestro exitosamente"

# Actualizar la tabla de estado
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "UPDATE system_status SET node_name = 'promoted_master', last_updated = CURRENT_TIMESTAMP WHERE node_name = '$(hostname)';"