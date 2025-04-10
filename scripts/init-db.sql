-- Crear usuario para replicación
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'replpass';

-- Crear tabla solicitada
CREATE TABLE groupFive(
  groupFive_id serial PRIMARY KEY,
  name_integrant varchar(50) NOT NULL,
  color_favorite varchar(50) NOT NULL
);

-- Insertar datos iniciales
INSERT INTO groupFive (name_integrant, color_favorite) 
VALUES 
  ('Samir Molinares', 'Azul'),
  ('Karen Peña', 'Verde'),
  ('Lunna Sosa', 'Rosa');

-- Crear tabla adicional para pruebas
CREATE TABLE system_status (
  status_id serial PRIMARY KEY,
  node_name varchar(50) NOT NULL,
  is_online boolean DEFAULT true,
  last_updated timestamp DEFAULT CURRENT_TIMESTAMP
);

-- Insertar datos de prueba
INSERT INTO system_status (node_name) 
VALUES 
  ('master'),
  ('replica1'),
  ('replica2');