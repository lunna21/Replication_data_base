# Eliminar todo para empezar de cero
sudo docker-compose down --volumes --remove-orphans

# Asegurar que el script de failover tenga los permisos adecuados
chmod +x ./scripts/failover.sh

# Iniciar en secuencia para asegurar orden correcto
sudo docker-compose up -d postgres-master
sleep 15
sudo docker-compose up -d postgres-replica1 postgres-replica2 postgres-replica3
sleep 10
sudo docker-compose up -d pgpool
sudo docker-compose ps
sudo ./scripts/setup-replication.sh