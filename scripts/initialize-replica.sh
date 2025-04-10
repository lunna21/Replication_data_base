#!/bin/bash
set -e

# Verificar que las variables de entorno necesarias están configuradas
REQUIRED_VARS=("POSTGRES_PASSWORD" "PRIMARY_HOST" "PRIMARY_PORT" "POSTGRES_USER" "POSTGRES_DB" "PGDATA" "REPLICATION_USER" "REPLICATION_PASSWORD")
for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    echo "Error: La variable de entorno $VAR no está configurada."
    exit 1
  fi
done

# Añadir retardo y reintentos
echo "Iniciando configuración de réplica..."
echo "Esperando a que el maestro esté completamente disponible..."
for i in {1..30}; do
  if PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$POSTGRES_USER"; then
    echo "Maestro disponible, continuando con la configuración..."
    break
  fi
  echo "Esperando al maestro (intento $i/30)..."
  sleep 2
  if [ $i -eq 30 ]; then
    echo "Error: El maestro no está disponible después de 60 segundos"
    exit 1
  fi
done

# Determinar el slot de replicación basado en el nombre del contenedor
CONTAINER_NAME=$(hostname)
if [[ "$CONTAINER_NAME" == *"replica1"* ]]; then
  SLOT_NAME="replica1_slot"
  echo "Usando slot replica1_slot para $CONTAINER_NAME"
elif [[ "$CONTAINER_NAME" == *"replica2"* ]]; then
  SLOT_NAME="replica2_slot"
  echo "Usando slot replica2_slot para $CONTAINER_NAME"
else
  # Para nuevos nodos dinámicos
  SLOT_NAME="${CONTAINER_NAME}_slot"
  echo "Usando slot dinámico $SLOT_NAME para $CONTAINER_NAME"
  
  # Verificar si el slot ya existe antes de crearlo
  SLOT_EXISTS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$PRIMARY_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$SLOT_NAME'" | tr -d ' ')
  
  if [ "$SLOT_EXISTS" = "0" ]; then
    echo "Creando slot de replicación $SLOT_NAME en el maestro..."
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$PRIMARY_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT pg_create_physical_replication_slot('$SLOT_NAME');"
  else
    echo "Slot $SLOT_NAME ya existe en el maestro"
  fi
fi

# El resto del script se mantiene igual
echo "Deteniendo PostgreSQL si está ejecutándose"
pg_ctl -D "$PGDATA" -m fast -w stop || true

echo "Limpiando el directorio de datos"
rm -rf "$PGDATA"/*

echo "Iniciando base backup desde $PRIMARY_HOST:$PRIMARY_PORT usando usuario $REPLICATION_USER y slot $SLOT_NAME"

# Iniciar la recuperación desde el master con más detalles de error
echo "Ejecutando: pg_basebackup -h $PRIMARY_HOST -p $PRIMARY_PORT -U $REPLICATION_USER -D $PGDATA -Fp -Xs -R -S $SLOT_NAME -v"
PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$REPLICATION_USER" -D "$PGDATA" -Fp -Xs -R -S "$SLOT_NAME" -v

# Configuración adicional para replicación
echo "Configurando postgresql.auto.conf para replicación"
cat > "$PGDATA/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=$PRIMARY_HOST port=$PRIMARY_PORT user=$REPLICATION_USER password=$REPLICATION_PASSWORD application_name=$(hostname)'
primary_slot_name = '$SLOT_NAME'
recovery_target_timeline = 'latest'
EOF

# Señalizar que es un servidor en espera (standby)
touch "$PGDATA/standby.signal"

echo "Nodo réplica $(hostname) inicializado correctamente"

# Opción 1: Usar una ruta completa donde PostgreSQL tenga permisos
echo "Iniciando servidor PostgreSQL..."
pg_ctl -D "$PGDATA" -l "$PGDATA/startup.log" start