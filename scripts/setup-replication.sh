#!/bin/bash
set -e

# Verificar la replicación y el estado de los nodos
check_replication() {
  echo "Verificando estado de replicación..."
  docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_stat_replication;"
  
  echo "Verificando slots de replicación..."
  docker exec postgres-master psql -U postgres -c "SELECT * FROM pg_replication_slots;"
  
  echo "Verificando consistencia de datos..."
  MASTER_COUNT=$(docker exec postgres-master psql -U postgres -d distribuida_db -t -c "SELECT COUNT(*) FROM groupFive;")
  REPLICA1_COUNT=$(docker exec postgres-replica1 psql -U postgres -d distribuida_db -t -c "SELECT COUNT(*) FROM groupFive;")
  REPLICA2_COUNT=$(docker exec postgres-replica2 psql -U postgres -d distribuida_db -t -c "SELECT COUNT(*) FROM groupFive;")
  
  echo "Registros en Master: $MASTER_COUNT"
  echo "Registros en Replica1: $REPLICA1_COUNT"
  echo "Registros en Replica2: $REPLICA2_COUNT"
  
  if [ "$MASTER_COUNT" = "$REPLICA1_COUNT" ] && [ "$MASTER_COUNT" = "$REPLICA2_COUNT" ]; then
    echo "✅ Replicación funcionando correctamente. Los datos están sincronizados."
  else
    echo "❌ Hay inconsistencias en los datos. Revise la configuración de replicación."
  fi
}

# Agregar un registro para probar la replicación
test_replication() {
  echo "Agregando un nuevo registro en el nodo maestro..."
  docker exec postgres-master psql -U postgres -d distribuida_db -c "INSERT INTO groupFive (name_integrant, color_favorite) VALUES ('Test User', 'Test Color');"
  
  echo "Esperando 5 segundos para la replicación..."
  sleep 5
  
  check_replication
}

# Simular caída del master
simulate_master_failure() {
  echo "Simulando falla del nodo maestro..."
  
  # Comprobar la ruta correcta de los binarios de pgpool en Bitnami
  echo "Verificando rutas de pgpool..."
  docker exec pgpool bash -c "find / -name 'pgpool' 2>/dev/null || echo 'No se encontró pgpool'"
  
  # La ruta correcta para el archivo de configuración de Bitnami
  PGPOOL_CONF="/opt/bitnami/pgpool/conf/pgpool.conf"
  
  # Verificar si el archivo existe
  echo "Verificando archivo de configuración de pgpool..."
  docker exec pgpool bash -c "ls -la /opt/bitnami/pgpool/conf/"
  
  # Asegurarse de que failover_on_backendsimulate_master_error esté activado (hacer un respaldo primero)
  echo "Activando failover automático en pgpool..."
  docker exec pgpool bash -c "cp $PGPOOL_CONF ${PGPOOL_CONF}.bak"
  docker exec pgpool bash -c "grep -q 'failover_on_backend_error' $PGPOOL_CONF && sed -i 's/failover_on_backend_error = off/failover_on_backend_error = on/g' $PGPOOL_CONF || echo 'failover_on_backend_error = on' >> $PGPOOL_CONF"
  
  # Reiniciar pgpool para aplicar la configuración
  echo "Reiniciando pgpool para aplicar la configuración..."
  docker restart pgpool
  sleep 20
  
  # Verificar el estado inicial de pgpool
  echo "Estado inicial de pgpool:"
  docker exec pgpool psql -h localhost -p 5432 -U postgres -c "SHOW pool_nodes;"
  
  # Detener el maestro
  echo "Deteniendo el nodo maestro..."
  docker stop postgres-master
  
  echo "Esperando 20 segundos para que pgpool detecte la falla..."
  sleep 20
  
  # Verificar estado pgpool después de la falla
  echo "Estado de pgpool después de la falla del maestro:"
  docker exec pgpool psql -h localhost -p 5432 -U postgres -c "SHOW pool_nodes;" || echo "⚠️ No se pudo conectar a pgpool."
  
  # Promoción manual de replica1 a maestro
  echo "Promoviendo replica1 a maestro manualmente..."
  docker exec postgres-replica1 su postgres -c "pg_ctl promote -D /var/lib/postgresql/data/pgdata"
  
  echo "Esperando 20 segundos para la promoción completa..."
  sleep 20
  
  echo "Verificando que replica1 ya no está en modo recuperación..."
  docker exec postgres-replica1 psql -U postgres -c "SELECT pg_is_in_recovery();"
  
  echo "Verificando que replica1 puede recibir escrituras..."
  docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "INSERT INTO groupFive (name_integrant, color_favorite) VALUES ('Direct Test', 'Direct Color');"
  
  # Crear slots de replicación en el nuevo maestro
  echo "Creando slots de replicación en el nuevo maestro..."
  docker exec postgres-replica1 psql -U postgres -c "SELECT pg_create_physical_replication_slot('replica2_slot');"
  docker exec postgres-replica1 psql -U postgres -c "SELECT pg_create_physical_replication_slot('replica3_slot');"

  # Reconfigurar replica2 para apuntar al nuevo maestro
  echo "Reconfigurando replica2 para apuntar al nuevo maestro..."
  docker exec postgres-replica2 bash -c "rm -rf /var/lib/postgresql/data/pgdata/recovery.* || true"
  docker exec postgres-replica2 bash -c "cat > /var/lib/postgresql/data/pgdata/postgresql.auto.conf << EOF

primary_conninfo = 'host=postgres-replica1 port=5432 user=replicator password=replpass application_name=postgres_replica2'
primary_slot_name = 'replica2_slot'
recovery_target_timeline = 'latest'
EOF"

  # Reconfigurar replica3 para apuntar al nuevo maestro
  echo "Reconfigurando replica3 para apuntar al nuevo maestro..."
  docker exec postgres-replica3 bash -c "rm -rf /var/lib/postgresql/data/pgdata/recovery.* || true"
  docker exec postgres-replica3 bash -c "cat > /var/lib/postgresql/data/pgdata/postgresql.auto.conf << EOF
primary_conninfo = 'host=postgres-replica1 port=5432 user=replicator password=replpass application_name=postgres_replica3'
primary_slot_name = 'replica3_slot'
recovery_target_timeline = 'latest'
EOF"

  # Asegurarse de que los archivos standby.signal existen
  docker exec postgres-replica2 bash -c "touch /var/lib/postgresql/data/pgdata/standby.signal"
  docker exec postgres-replica3 bash -c "touch /var/lib/postgresql/data/pgdata/standby.signal"

  # Reiniciar las réplicas para que tomen la nueva configuración
  echo "Reiniciando réplicas para conectarse al nuevo maestro..."
  docker restart postgres-replica2 postgres-replica3

  # Modificar la configuración de pgpool directamente para que reconozca el nuevo maestro
  echo "Modificando la configuración de pgpool para reconocer el nuevo maestro..."
  
  # Crear un script para reconfiguraciones
  docker exec pgpool bash -c "cat > /tmp/update_primary.sh << 'EOF'
#!/bin/bash
# Actualizar backend_flag del antiguo master (0) y nuevo master (1)
sed -i 's/backend_flag0 = 1/backend_flag0 = 0/g' $PGPOOL_CONF 2>/dev/null || echo "backend_flag0 = 0" >> $PGPOOL_CONF
sed -i 's/backend_flag1 = 0/backend_flag1 = 1/g' $PGPOOL_CONF 2>/dev/null || echo "backend_flag1 = 1" >> $PGPOOL_CONF
echo "Configuración actualizada para nuevo maestro"
EOF"
  
  docker exec pgpool bash -c "chmod +x /tmp/update_primary.sh"
  docker exec pgpool bash -c "/tmp/update_primary.sh"
  
  # Reiniciar pgpool para aplicar cambios
  echo "Reiniciando pgpool para aplicar la nueva configuración..."
  docker restart pgpool
  sleep 30
  
  # Verificar conexión a pgpool después del reinicio
  echo "Verificando conexión a través de pgpool después del reinicio..."
  docker exec pgpool psql -h localhost -p 5432 -U postgres -c "SELECT 1 AS test_connection;" || \
    echo "No se puede conectar a pgpool. Podría ser necesario un reinicio adicional."
  
  # Intentar insertar datos a través de pgpool
  echo "Intentando insertar datos a través de pgpool..."
  docker exec pgpool psql -h localhost -p 5432 -U postgres -d distribuida_db -c "INSERT INTO groupFive (name_integrant, color_favorite) VALUES ('Via PgPool', 'Pgpool Color');" || \
    echo "❌ Inserción a través de pgpool falló. Intentando directamente en el nodo maestro."
  
  # Verificar datos en replica1
  echo "Verificando datos en replica1 directamente:"
  docker exec postgres-replica1 psql -U postgres -d distribuida_db -c "SELECT * FROM groupFive ORDER BY groupFive_id DESC LIMIT 3;"
  
  # Reiniciar y configurar antiguo maestro como réplica
  echo "Reiniciando el antiguo nodo maestro como réplica..."
  docker start postgres-master
  sleep 15
  
  # Limpiar configuración antigua y crear archivos para modo standby en PostgreSQL 13+
  echo "Configurando el antiguo maestro para seguir al nuevo maestro..."
  docker exec postgres-master bash -c "rm -rf /var/lib/postgresql/data/pgdata/recovery.* || true"
  docker exec postgres-master bash -c "touch /var/lib/postgresql/data/pgdata/standby.signal"
  docker exec postgres-master bash -c "cat > /var/lib/postgresql/data/pgdata/postgresql.auto.conf << EOF
primary_conninfo = 'host=postgres-replica1 port=5432 user=postgres password=postgres application_name=postgres_master'
recovery_target_timeline = 'latest'
EOF"
  
  # Reiniciar el antiguo maestro para aplicar cambios
  echo "Reiniciando el antiguo maestro para aplicar configuración de réplica..."
  docker restart postgres-master
  sleep 30
  
  # Verificar estado de recuperación del antiguo maestro
  echo "Verificando si el antiguo maestro ahora es una réplica:"
  docker exec postgres-master psql -U postgres -c "SELECT pg_is_in_recovery();" || \
    echo "❌ No se pudo conectar al antiguo maestro."
  
  # Reiniciar pgpool para reconocer todos los cambios
  echo "Reiniciando pgpool una última vez para reconocer todos los cambios..."
  docker restart pgpool
  sleep 30
  
  # Verificar configuración final
  echo "Configuración final de pgpool:"
  docker exec pgpool psql -h localhost -p 5432 -U postgres -c "SHOW pool_nodes;" || \
    echo "❌ No se puede verificar el estado final de pgpool."
  
  echo "✅ Proceso de failover completado."
}

# Menú de opciones
echo "Seleccione una opción:"
echo "1. Verificar estado de replicación"
echo "2. Probar replicación agregando un registro"
echo "3. Simular falla del nodo maestro"

read -p "Opción: " option

case $option in
  1)
    check_replication
    ;;
  2)
    test_replication
    ;;
  3)
    simulate_master_failure
    ;;
  *)
    echo "Opción no válida"
    ;;
esac