#!/bin/bash

echo "=== PRUEBA DE FAILOVER ==="
echo "1. Estado inicial de la configuración"
echo "-------------------------------"

# Verificar la configuración actual de nodos
echo "Nodos configurados en PgPool:"
sudo docker exec pgpool psql -U postgres -h pgpool -p 5432 -c "SHOW pool_nodes;"

# Verificar quién es el maestro actual
echo -e "\nConexiones de replicación actuales:"
sudo docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Crear tabla de prueba en el maestro
echo -e "\nCreando tabla de prueba e insertando datos..."
sudo docker exec pgpool psql -U postgres -h pgpool -p 5432 -d distribuida_db -c "
CREATE TABLE IF NOT EXISTS failover_test (
  id SERIAL PRIMARY KEY, 
  data TEXT, 
  timestamp TIMESTAMP DEFAULT NOW()
);"
sudo docker exec pgpool psql -U postgres -h pgpool -p 5432 -d distribuida_db -c "
INSERT INTO failover_test (data) VALUES ('Dato antes del failover');"

# Verificamos que se insertó correctamente
echo -e "\nDatos antes del failover:"
sudo docker exec pgpool psql -U postgres -h pgpool -p 5432 -d distribuida_db -c "SELECT * FROM failover_test;"

# SIMULAMOS EL FALLO DEL NODO MAESTRO
echo -e "\n2. Simulando fallo del nodo maestro"
echo "-------------------------------"
echo "Deteniendo el contenedor postgres-master..."
sudo docker stop postgres-master

# Esperamos a que PgPool detecte el fallo y realice el failover
echo "Esperando 30 segundos para que PgPool detecte el fallo y realice el failover..."
sleep 30

# Verificamos el nuevo estado de los nodos
echo -e "\n3. Estado después del failover"
echo "-------------------------------"
echo "Nodos en PgPool después del failover:"
sudo docker exec pgpool psql -U postgres -h pgpool -p 5432 -c "SHOW pool_nodes;"

# Intentamos insertar nuevos datos a través de PgPool
echo -e "\nInsertando nuevos datos después del failover..."
sudo docker exec pgpool psql -U postgres -h pgpool -p 5432 -d distribuida_db -c "
INSERT INTO failover_test (data) VALUES ('Dato después del failover');"

# Verificamos que los datos se insertaron correctamente
echo -e "\nDatos después del failover:"
sudo docker exec pgpool psql -U postgres -h pgpool -p 5432 -d distribuida_db -c "SELECT * FROM failover_test;"

# Verificamos el archivo de log del failover
echo -e "\n4. Log del failover"
echo "-------------------------------"
echo "Contenido del log de failover:"
sudo docker exec pgpool cat /var/log/postgresql/failover.log

# Restauramos el nodo maestro original
echo -e "\n5. Restaurando el nodo maestro original"
echo "-------------------------------"
echo "Iniciando el contenedor postgres-master..."
sudo docker start postgres-master

echo -e "\nPrueba de failover completada."