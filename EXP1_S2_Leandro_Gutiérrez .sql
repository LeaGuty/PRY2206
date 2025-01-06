-- Declarar variable de entrada para el periodo
VAR B_FECHA VARCHAR2(10);
EXEC :B_FECHA := '03/2024';

DECLARE
    -- Variables para almacenar registros y valores temporales
    R_DETALLE DETALLE_DE_CLIENTES%ROWTYPE; -- Registro para insertar en la tabla detalle
    V_MINID NUMBER;                       -- ID mánimo de clientes
    V_MAXID NUMBER;                       -- ID máximo de clientes
    V_RENTA NUMBER;                       -- Renta del cliente
    V_TIPOCLI VARCHAR(1);                 -- Tipo de cliente (código)
    V_NTIPOCLI VARCHAR(15);               -- Nombre del tipo de cliente
    V_IDCOMUNA NUMBER;                    -- ID de la comuna del cliente
    V_COMUNA VARCHAR(30);                 -- Nombre de la comuna
    V_PORCENT_EDAD NUMBER;                -- Porcentaje según tramo de edad
    V_CONTADOR NUMBER := 0;               -- Contador de clientes procesados
    V_TOTAL NUMBER := 0;                  -- Total de clientes a procesar
BEGIN
    -- Mensaje inicial
    DBMS_OUTPUT.PUT_LINE('PROCESANDO CLIENTES...');

    -- Limpiar la tabla de detalles
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_DE_CLIENTES';

    -- Obtener el total de clientes para la validación
    SELECT COUNT(*) INTO V_TOTAL FROM CLIENTE;

    -- Obtener el rango de IDs de los clientes
    SELECT MIN(ID_CLI), MAX(ID_CLI)
    INTO V_MINID, V_MAXID
    FROM CLIENTE;

    -- Iterar sobre los clientes en el rango
    WHILE V_MINID <= V_MAXID LOOP
        -- Asignar el ID del cliente al registro de detalle
        R_DETALLE.IDC := V_MINID;

        -- Obtener información del cliente actual
        SELECT NUMRUN_CLI, 
               INITCAP(APPATERNO_CLI || ' ' || APMATERNO_CLI || ' ' || PNOMBRE_CLI), 
               FLOOR(MONTHS_BETWEEN(SYSDATE, FECHA_NAC_CLI) / 12), 
               LOWER(APPATERNO_CLI) || FLOOR(MONTHS_BETWEEN(SYSDATE, FECHA_NAC_CLI) / 12) || '*' || 
               UPPER(SUBSTR(PNOMBRE_CLI, 1, 1)) || TO_CHAR(FECHA_NAC_CLI, 'DD') || 
               TO_NUMBER(SUBSTR(:B_FECHA, 1, 2)) || '@LogiCarg.cl', 
               RENTA, ID_TIPO_CLI, ID_COMUNA
        INTO R_DETALLE.RUT, R_DETALLE.CLIENTE, R_DETALLE.EDAD, R_DETALLE.CORREO_CORP, 
             V_RENTA, V_TIPOCLI, V_IDCOMUNA
        FROM CLIENTE
        WHERE ID_CLI = V_MINID;

        -- Obtener el nombre del tipo de cliente
        SELECT NOMBRE_TIPO_CLI
        INTO V_NTIPOCLI
        FROM TIPO_CLIENTE
        WHERE ID_TIPO_CLI = V_TIPOCLI;

        -- Obtener el nombre de la comuna
        SELECT NOMBRE_COMUNA
        INTO V_COMUNA
        FROM COMUNA
        WHERE ID_COMUNA = V_IDCOMUNA;

        -- Calcular el puntaje según las reglas de negocio
        IF V_RENTA > 700000 AND V_COMUNA NOT IN ('La Reina', 'Las Condes', 'Vitacura') THEN
            R_DETALLE.PUNTAJE := ROUND(V_RENTA * 0.03);
        ELSIF V_NTIPOCLI IN ('VIP', 'Extranjero') THEN
            R_DETALLE.PUNTAJE := R_DETALLE.EDAD * 30;
        ELSE
            SELECT PORCENTAJE
            INTO V_PORCENT_EDAD
            FROM TRAMO_EDAD
            WHERE EXTRACT(YEAR FROM SYSDATE) = ANNO_VIG
              AND TRAMO_INF <= R_DETALLE.EDAD 
              AND TRAMO_SUP >= R_DETALLE.EDAD;

            R_DETALLE.PUNTAJE := ROUND(V_RENTA * V_PORCENT_EDAD / 100);
        END IF;

        -- Asignar el periodo
        R_DETALLE.PERIODO := :B_FECHA;

        -- Insertar el registro en la tabla de detalles
        INSERT INTO DETALLE_DE_CLIENTES VALUES R_DETALLE;

        -- Incrementar el ID y el contador
        V_MINID := V_MINID + 5;
        V_CONTADOR := V_CONTADOR + 1;
    END LOOP;

    -- Validar si el proceso fue exitoso
    IF V_CONTADOR = V_TOTAL THEN
        DBMS_OUTPUT.PUT_LINE('Proceso Finalizado Exitosamente');
        DBMS_OUTPUT.PUT_LINE('Se Procesaron : ' || V_CONTADOR || ' CLIENTES');
        COMMIT;
    ELSE
        DBMS_OUTPUT.PUT_LINE('Error en el proceso. ROLLBACK ejecutado.');
        ROLLBACK;
    END IF;
END;


/*
SELECT * FROM DETALLE_DE_CLIENTES;

SELECT * FROM CLIENTE;

SELECT * FROM TRAMO_EDAD;

SELECT NUMRUN_CLI, INITCAP(APPATERNO_CLI || ' ' || APMATERNO_CLI || ' ' || PNOMBRE_CLI ) 
        , FLOOR(MONTHS_BETWEEN(SYSDATE, FECHA_NAC_CLI) / 12), LOWER(APPATERNO_CLI) || FLOOR(MONTHS_BETWEEN(SYSDATE, FECHA_NAC_CLI) / 12)||'*'|| UPPER(SUBSTR(PNOMBRE_CLI, 1, 1)) ||TO_CHAR(FECHA_NAC_CLI, 'DD')||TO_NUMBER(SUBSTR('03/2024', 1, 2))||'@LogiCarg.cl' 
            --INTO R_DETALLE.RUT, R_DETALLE.CLIENTE,R_DETALLE.EDAD
        FROM CLIENTE 
        WHERE ID_CLI =  10;


SELECT * FROM TIPO_CLIENTE;

SELECT * FROM COMUNA;
*/