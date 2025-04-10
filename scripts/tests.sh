# Verificar que las réplicas están conectadas al maestro
sudo docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Verificar slots de replicación
sudo docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_replication_slots;"

# Crear tabla de prueba en el maestro
sudo docker exec postgres-master psql -U postgres -d distribuida_db -c "CREATE TABLE IF NOT EXISTS test_replication (id SERIAL PRIMARY KEY, data TEXT, timestamp TIMESTAMP DEFAULT NOW());"

# Insertar datos en el maestro
sudo docker exec postgres-master psql -U postgres -d distribuida_db -c "INSERT INTO test_replication (data) VALUES ('Test desde maestro');"

# Verificar que los datos se replican a las réplicas (debe mostrar el registro)
sudo docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "SELECT * FROM test_replication;"

# Verificar que los datos se replican a las réplicas (debe mostrar el registro)
sudo docker exec postgres-replica2 psql -U postgres -d distribuida_db -c "SELECT * FROM test_replication;"

# Verificar que los datos se replican a las réplicas (debe mostrar el registro)
sudo docker exec postgres-master psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive;"

sudo docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive;"

sudo docker exec postgres-master psql -U postgres -d distribuida_db -c "INSERT INTO groupFive (name_integrant, color_favorite) 
VALUES ('Laura Molinares', 'Rosado');"

sudo docker exec postgres-master psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive;"

sudo docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "INSERT INTO groupFive (name_integrant, color_favorite) 
VALUES ('TEST', 'TEST');"
sudo docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive;"
sudo docker exec postgres-replica2 psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive;"


sudo docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "INSERT INTO groupFive (name_integrant, color_favorite) 
VALUES ('TEST', 'TEST');"
sudo docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive;"
sudo docker exec postgres-replica4 psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive;"


