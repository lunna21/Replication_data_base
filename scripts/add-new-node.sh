#!/bin/bash
# filepath: /home/lunnis/Sis_distribuidos/proyecto-db-distribuida/scripts/add-new-node.sh
set -e

# Este script se ejecuta desde el host para añadir un nuevo nodo réplica
# Uso: ./add-new-node.sh numero_replica

if [ -z "$1" ]; then
  echo "Debe especificar un número para la réplica"
  echo "Uso: ./add-new-node.sh numero_replica"
  exit 1
fi

# Obtener la ruta del directorio raíz del proyecto
if [[ $0 == /* ]]; then
  # Si la ruta es absoluta
  SCRIPT_DIR=$(dirname "$0")
  ROOT_DIR=$(dirname "$SCRIPT_DIR")
else
  # Si la ruta es relativa
  SCRIPT_DIR=$(dirname "$0")
  if [[ $SCRIPT_DIR == "." ]]; then
    ROOT_DIR=".."
  else
    ROOT_DIR=$(dirname "$SCRIPT_DIR")
  fi
fi

cd "$ROOT_DIR"
echo "Trabajando en el directorio: $(pwd)"

REPLICA_NUM=$1
REPLICA_NAME="postgres-replica$REPLICA_NUM"
REPLICA_PORT=$((5434 + $REPLICA_NUM - 2))  # Incrementamos a partir de 5434

# Convertir nombre válido para slot (sin guiones)
SLOT_NAME="postgres_replica${REPLICA_NUM}_slot"

# Preparar configuraciones en archivos separados
cat > "replica_service.yml" <<EOF
  # Réplica $REPLICA_NUM (Añadida dinámicamente)
  $REPLICA_NAME:
    image: postgres:\${PG_VERSION}
    container_name: $REPLICA_NAME
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data/pgdata
      PRIMARY_HOST: postgres-master
      PRIMARY_PORT: \${POSTGRES_PORT:-5432}
      REPLICATION_USER: \${REPLICATION_USER}
      REPLICATION_PASSWORD: \${REPLICATION_PASSWORD}
      SLOT_NAME: $SLOT_NAME
    volumes:
      - $REPLICA_NAME-data:/var/lib/postgresql/data
      - ./config/postgresql.conf.replica:/etc/postgresql/postgresql.conf
      - ./config/pg_hba.conf:/etc/postgresql/pg_hba.conf
      - ./scripts/initialize-replica.sh:/docker-entrypoint-initdb.d/initialize-replica.sh
    command: postgres -c 'config_file=/etc/postgresql/postgresql.conf'
    ports:
      - "$REPLICA_PORT:5432"
    depends_on:
      postgres-master:
        condition: service_healthy
    networks:
      - postgres-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

cat > "volume_config.yml" <<EOF
  $REPLICA_NAME-data:
EOF

# Método alternativo para modificar docker-compose.yml
# Crear un archivo temporal con todo el contenido
awk -v r="$(cat replica_service.yml)" '/^networks:/{print r; print; next} 1' docker-compose.yml > docker-compose.temp1
awk -v v="$(cat volume_config.yml)" '/^volumes:/{print $0; print v; next} 1' docker-compose.temp1 > docker-compose.temp2

# Reemplazar el archivo original
mv docker-compose.temp2 docker-compose.yml
rm -f docker-compose.temp1

# Eliminar archivos temporales
rm -f replica_service.yml volume_config.yml

# Añadir slot de replicación en el nodo maestro con nombre válido
docker exec postgres-master psql -U postgres -d distribuida_db -c "SELECT pg_create_physical_replication_slot('${SLOT_NAME}');"

# Actualizar pgpool con el nuevo backend
# Obtenemos la configuración actual
CURRENT_BACKENDS=$(docker exec pgpool env | grep PGPOOL_BACKEND_NODES || echo "PGPOOL_BACKEND_NODES=0:postgres-master:5432:1:ALWAYS_PRIMARY,1:postgres-replica1:5432:1:ALLOW_TO_FAILOVER,2:postgres-replica2:5432:1:ALLOW_TO_FAILOVER")
# Extraemos el último número de backend
LAST_BACKEND_ID=$(echo $CURRENT_BACKENDS | grep -oP '\d+(?=:[^,]+$)' || echo "2")
# Reemplaza la línea 99 con este código más simple
LAST_BACKEND_ID=2
# Si el contenedor pgpool existe, intentamos obtener el último ID
if docker ps -a | grep -q "pgpool"; then
  CURRENT_NODES=$(docker exec pgpool env | grep PGPOOL_BACKEND_NODES || echo "")
  if [[ ! -z "$CURRENT_NODES" ]]; then
    # Contamos las comas para saber cuántos backends hay
    NODE_COUNT=$(echo "$CURRENT_NODES" | tr -cd ',' | wc -c)
    LAST_BACKEND_ID=$NODE_COUNT
  fi
fi
NEW_BACKEND_ID=$((LAST_BACKEND_ID + 1))

# Actualizamos la configuración de pgpool
NEW_BACKENDS="${CURRENT_BACKENDS#*=}"
NEW_BACKENDS="${NEW_BACKENDS%\"}"
NEW_BACKENDS="$NEW_BACKENDS,$NEW_BACKEND_ID:$REPLICA_NAME:5432:1:ALLOW_TO_FAILOVER"
docker-compose stop pgpool
docker-compose rm -f pgpool

# Actualizar la variable de entorno en el docker-compose
sed -i "s|PGPOOL_BACKEND_NODES: .*|PGPOOL_BACKEND_NODES: $NEW_BACKENDS|g" docker-compose.yml

# Actualizar la lista de hosts de postgres
CURRENT_HOSTS=$(grep "PGPOOL_POSTGRES_HOSTS:" docker-compose.yml | cut -d ':' -f 2- | xargs)
NEW_HOSTS="$CURRENT_HOSTS,$REPLICA_NAME"
sed -i "s|PGPOOL_POSTGRES_HOSTS: .*|PGPOOL_POSTGRES_HOSTS: $NEW_HOSTS|g" docker-compose.yml

# Iniciar los nuevos servicios
docker-compose up -d $REPLICA_NAME pgpool

echo "Nuevo nodo $REPLICA_NAME añadido exitosamente con puerto $REPLICA_PORT"