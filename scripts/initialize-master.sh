#!/bin/bash
echo "Script initialize-master.sh iniciando..."

# Crear directorio para archivos WAL
mkdir -p /var/lib/postgresql/archive
chmod 700 /var/lib/postgresql/archive

# Crear slot de replicación para cada réplica
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  SELECT pg_create_physical_replication_slot('replica1_slot');
  SELECT pg_create_physical_replication_slot('replica2_slot');
EOSQL

echo "Nodo maestro inicializado correctamente con slots de replicación"