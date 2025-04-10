#!/bin/bash
# Script para manejar el failover automático desde pgpool

# Parametros pasados por pgpool
FAILED_NODE=$1       # ID del nodo que falló
FAILED_HOST=$2       # Host del nodo que falló
FAILED_PORT=$3       # Puerto del nodo que falló
FAILED_DB=$4         # Nombre de la BD
NEW_MASTER_ID=$5     # ID del nuevo maestro
NEW_MASTER_HOST=$6   # Host del nuevo maestro
OLD_MASTER_ID=$7     # ID del antiguo maestro
OLD_PRIMARY_HOST=$8  # Host del antiguo maestro

# Directorio para logs
LOG_DIR="/var/log/postgresql"
mkdir -p $LOG_DIR

# Registrar la ejecución
echo "[$(date)] Ejecutando failover. Nodo fallido: $FAILED_NODE, Nuevo maestro: $NEW_MASTER_ID ($NEW_MASTER_HOST)" >> $LOG_DIR/failover.log

# Promover la réplica a nuevo maestro
if [ "$NEW_MASTER_HOST" != "" ]; then
  echo "Promoviendo $NEW_MASTER_HOST a maestro" >> $LOG_DIR/failover.log
  
  # Usar psql para conectarse directamente al nuevo maestro y ejecutar el comando de promoción
  # Utilizamos la comunicación directa entre contenedores a través de la red de Docker
  PGPASSWORD=postgres psql -h $NEW_MASTER_HOST -U postgres -c "SELECT pg_promote(true);" >> $LOG_DIR/failover.log 2>&1
  
  # Esperar a que la promoción se complete
  echo "Esperando 10 segundos para completar la promoción..." >> $LOG_DIR/failover.log
  sleep 10
  
  # Crear slots de replicación en el nuevo maestro para las otras réplicas
  # Extraemos el nombre de la réplica del hostname (postgres-replica1 -> replica1)
  NEW_MASTER_NAME=${NEW_MASTER_HOST#postgres-}
  
  echo "Configurando slots de replicación en el nuevo maestro $NEW_MASTER_NAME" >> $LOG_DIR/failover.log
  
  for REPLICA in replica1 replica2 replica3; do
    if [ "$REPLICA" != "$NEW_MASTER_NAME" ]; then
      echo "Creando slot para $REPLICA" >> $LOG_DIR/failover.log
      PGPASSWORD=postgres psql -h $NEW_MASTER_HOST -U postgres -c \
        "SELECT pg_create_physical_replication_slot('${REPLICA}_slot') ON CONFLICT DO NOTHING;" >> $LOG_DIR/failover.log 2>&1
    fi
  done
  
  # Notificar éxito
  echo "El nodo $NEW_MASTER_HOST ha sido promovido exitosamente" >> $LOG_DIR/failover.log
  exit 0
else
  echo "Error: No se especificó un nuevo nodo maestro" >> $LOG_DIR/failover.log
  exit 1
fi