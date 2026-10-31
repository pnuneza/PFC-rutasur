-- ==========================================================
-- RutaSur v1.0 — 06_roles.sql
-- Rol de la aplicación con permisos mínimos (principio de menor privilegio)
--
-- El dueño del esquema (quien ejecuta estos scripts) crea y modifica tablas.
-- El backend se conecta con rutasur_app, que NO puede:
--   · crear, modificar ni borrar tablas
--   · borrar líneas, variantes, paraderos, unidades ni cuentas
--     (se desactivan con activa = false, así se conserva el historial)
--   · borrar posiciones directamente (solo vía fn_depurar_datos_operativos)
--   · modificar ni borrar la auditoría
--
-- Se ejecuta con psql pasando la contraseña como variable:
--   psql ... -v app_password='********' -f 06_roles.sql
-- ==========================================================

\if :{?app_password}
\else
    \echo 'ERROR: falta la variable app_password (psql -v app_password=...)'
    \quit
\endif

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rutasur_app') THEN
        CREATE ROLE rutasur_app LOGIN;
    END IF;
END
$$;

ALTER ROLE rutasur_app WITH LOGIN PASSWORD :'app_password';

-- Nadie más que el dueño crea objetos en el esquema
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT  USAGE  ON SCHEMA public TO rutasur_app;

-- Configuración: lectura y edición desde el panel, sin borrado
GRANT SELECT, INSERT, UPDATE ON linea, variante, paradero, unidad,
                                cuenta_conductor, cuenta_administrativa
      TO rutasur_app;

-- Orden de paraderos: se reemplaza completo al editar una variante
GRANT SELECT, INSERT, UPDATE, DELETE ON paradero_variante TO rutasur_app;

-- Operación: abrir/cerrar sesiones y recibir posiciones
GRANT SELECT, INSERT, UPDATE ON sesion_emision TO rutasur_app;
GRANT SELECT, INSERT         ON posicion       TO rutasur_app;

-- Auditoría: solo se agrega, nunca se modifica
GRANT SELECT, INSERT ON registro_evento TO rutasur_app;
GRANT USAGE ON SEQUENCE registro_evento_id_seq TO rutasur_app;

-- Vista y funciones
GRANT SELECT ON v_unidades_activas TO rutasur_app;
GRANT EXECUTE ON FUNCTION fn_recalcular_paraderos_variante(uuid, numeric),
                          fn_asignar_paraderos_variante(uuid, varchar[]),
                          fn_depurar_datos_operativos(integer)
      TO rutasur_app;

-- La depuración es la única vía para borrar datos operativos
REVOKE EXECUTE ON FUNCTION fn_depurar_datos_operativos(integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_depurar_datos_operativos(integer) TO rutasur_app;
