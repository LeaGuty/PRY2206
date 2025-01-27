-- Declaración de variables bind para el proceso
VAR B_FECHA VARCHAR2(10);
EXEC :B_FECHA := '06/2021';
VAR B_LIMIT NUMBER;
EXEC :B_LIMIT := 250000;

DECLARE
    -- Declaración de registros asociados a la tabla DETALLE_ASIGNACION_MES
    R_DETALLE DETALLE_ASIGNACION_MES%ROWTYPE;
    

    -- Declaración del cursor para profesionales
    CURSOR c_profesionales IS
        SELECT PR.NUMRUN_PROF,
               PR.NOMBRE,
               PR.APPATERNO,
               PR.COD_PROFESION,
               PROF.NOMBRE_PROFESION,
               PR.COD_TPCONTRATO,
               CO.NOM_COMUNA
        FROM PROFESIONAL PR
        JOIN COMUNA CO ON CO.COD_COMUNA = PR.COD_COMUNA
        JOIN PROFESION PROF ON PROF.COD_PROFESION = PR.COD_PROFESION
        ORDER BY PROF.NOMBRE_PROFESION, PR.APPATERNO, PR.NOMBRE;

    -- Variables auxiliares para los cálculos
    v_nombre        PROFESIONAL.NOMBRE%TYPE;
    v_appaterno     PROFESIONAL.APPATERNO%TYPE;
    v_codprofesion  PROFESIONAL.COD_PROFESION%TYPE;
    v_codcontrato   PROFESIONAL.COD_TPCONTRATO%TYPE;
    v_nom_comuna    COMUNA.NOM_COMUNA%TYPE;
    v_asignacion    NUMBER;
    v_incentivo     NUMBER;
    v_movil         NUMBER;
    v_asigtipocont  NUMBER;
    v_asigprof      NUMBER;
    v_mhonorario    NUMBER;
    v_cantasesoria  NUMBER;
    v_asigtotal     NUMBER;
    v_merror        VARCHAR(255);
    v_runformat     VARCHAR2(20);

    -- Variables para el mes y año de la fecha del proceso
    v_mes           NUMBER := TO_NUMBER(SUBSTR(:B_FECHA, 1, 2));
    v_anno          NUMBER := TO_NUMBER(SUBSTR(:B_FECHA, 4, 4));

    -- Variables con porcentajes según comuna
    v_stgo          NUMBER := 0.02;
    v_nuno          NUMBER := 0.04;
    v_rein          NUMBER := 0.05;
    v_flor          NUMBER := 0.07;
    v_macu          NUMBER := 0.09;

    -- Declaración de excepciones personalizadas
    v_error_id      NUMBER;
    e_asignacion_excedida EXCEPTION;

BEGIN
    -- Limpieza de las tablas y recreación de la secuencia de errores
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ASIGNACION_MES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_MES_PROFESION';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';

    EXECUTE IMMEDIATE 'DROP SEQUENCE sq_error';
    EXECUTE IMMEDIATE 'CREATE SEQUENCE sq_error START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE';

    -- Abrir el cursor para recorrer los profesionales
    OPEN c_profesionales;
    LOOP
        FETCH c_profesionales INTO R_DETALLE.RUN_PROFESIONAL, v_nombre, v_appaterno, 
                                 v_codprofesion, R_DETALLE.PROFESION, v_codcontrato, v_nom_comuna;
        EXIT WHEN c_profesionales%NOTFOUND;

        -- Formatear el RUN profesional
        v_runformat := LPAD(TO_CHAR(R_DETALLE.RUN_PROFESIONAL, 'FM99G999G999'), 10, '0');

        -- Obtener el porcentaje de asignación
        BEGIN
            SELECT ASIGNACION INTO v_asignacion
            FROM PORCENTAJE_PROFESION
            WHERE COD_PROFESION = v_codprofesion;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_merror := SQLERRM;
                INSERT INTO ERRORES_PROCESO 
                VALUES (sq_error.NEXTVAL, v_merror, 'Error al obtener el porcentaje de asignación para el run Nro. ' || v_runformat);
                COMMIT;
                v_asignacion := 0;
        END;

        -- Obtener el porcentaje de incentivo
        BEGIN
            SELECT INCENTIVO INTO v_incentivo
            FROM TIPO_CONTRATO
            WHERE COD_TPCONTRATO = v_codcontrato;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_merror := SQLERRM;
                INSERT INTO ERRORES_PROCESO 
                VALUES (sq_error.NEXTVAL, v_merror, 'Error al obtener el porcentaje de incentivo para el run Nro. ' || v_runformat);
                COMMIT;
                v_incentivo := 0;
        END;

        -- Calcular las asesorías y honorarios
        SELECT COUNT(PR.NUMRUN_PROF) AS NRO_ASESORIAS,
               SUM(ASE.HONORARIO) AS MONTO_HONORARIOS
        INTO v_cantasesoria, v_mhonorario
        FROM PROFESIONAL PR
        JOIN ASESORIA ASE ON ASE.NUMRUN_PROF = PR.NUMRUN_PROF
        WHERE PR.NUMRUN_PROF = R_DETALLE.RUN_PROFESIONAL
          AND TO_CHAR(ASE.INICIO_ASESORIA, 'MM/YYYY') = :B_FECHA;

        -- Calcular los montos de movilización según la comuna
        v_movil := CASE
                     WHEN v_nom_comuna = 'Santiago' AND v_mhonorario < 350000 THEN ROUND(v_mhonorario * v_stgo, 0)
                     WHEN v_nom_comuna = 'Ñuñoa' THEN ROUND(v_mhonorario * v_nuno, 0)
                     WHEN v_nom_comuna = 'La Reina' AND v_mhonorario < 400000 THEN ROUND(v_mhonorario * v_rein, 0)
                     WHEN v_nom_comuna = 'La Florida' AND v_mhonorario < 800000 THEN ROUND(v_mhonorario * v_flor, 0)
                     WHEN v_nom_comuna = 'Macul' AND v_mhonorario < 680000 THEN ROUND(v_mhonorario * v_macu, 0)
                     ELSE 0
                   END;

        -- Calcular las asignaciones totales
        v_asigtipocont := ROUND(v_mhonorario * v_incentivo / 100, 0);
        v_asigprof := ROUND(v_mhonorario * v_asignacion / 100, 0);

        BEGIN
            v_asigtotal := v_movil + v_asigtipocont + v_asigprof;

            -- Verificar si excede el límite permitido
            IF v_asigtotal > :B_LIMIT THEN
                RAISE e_asignacion_excedida;
            END IF;
        EXCEPTION
            WHEN e_asignacion_excedida THEN
                INSERT INTO ERRORES_PROCESO 
                VALUES (sq_error.NEXTVAL, 'Error: Asignación excedida para RUN ' || v_runformat, 
                        'Monto ajustado de ' || v_asigtotal || ' a ' || :B_LIMIT);
                COMMIT;
                v_asigtotal := :B_LIMIT;
        END;

        -- Asignar valores al registro
        R_DETALLE.MES_PROCESO := v_mes;
        R_DETALLE.ANNO_PROCESO := v_anno;
        R_DETALLE.NOMBRE_PROFESIONAL := v_nombre || ' ' || v_appaterno;
        R_DETALLE.NRO_ASESORIAS := v_cantasesoria;
        R_DETALLE.MONTO_HONORARIOS := v_mhonorario;
        R_DETALLE.MONTO_MOVIL_EXTRA := v_movil;
        R_DETALLE.MONTO_ASIG_TIPOCONT := v_asigtipocont;
        R_DETALLE.MONTO_ASIG_PROFESION := v_asigprof;
        R_DETALLE.MONTO_TOTAL_ASIGNACIONES := v_asigtotal;

        BEGIN
            INSERT INTO DETALLE_ASIGNACION_MES VALUES R_DETALLE;
        EXCEPTION
            WHEN OTHERS THEN
                v_merror := SQLERRM;
        END;
    END LOOP;

    -- Cerrar el cursor
    CLOSE c_profesionales;
    COMMIT;

    -- Insertar en el resumen mensual por profesión
    INSERT INTO RESUMEN_MES_PROFESION
    SELECT SUBSTR(:B_FECHA, 4, 4) || SUBSTR(:B_FECHA, 1, 2) AS ANNOMES_PROCESO,
           PROF.NOMBRE_PROFESION AS PROFESION,
           NVL(SUM(DAM.NRO_ASESORIAS), 0) AS TOTAL_ASESORIAS,
           NVL(SUM(DAM.MONTO_HONORARIOS), 0) AS MONTO_TOTAL_HONORARIOS,
           NVL(SUM(DAM.MONTO_MOVIL_EXTRA), 0) AS MONTO_TOTAL_MOVIL_EXTRA,
           NVL(SUM(DAM.MONTO_ASIG_TIPOCONT), 0) AS MONTO_TOTAL_ASIG_TIPOCONT,
           NVL(SUM(DAM.MONTO_ASIG_PROFESION), 0) AS MONTO_TOTAL_ASIG_PROFESION,
           NVL(SUM(DAM.MONTO_TOTAL_ASIGNACIONES), 0) AS MONTO_TOTAL_ASIGNACIONES
    FROM PROFESION PROF
    LEFT JOIN DETALLE_ASIGNACION_MES DAM ON DAM.PROFESION = PROF.NOMBRE_PROFESION
    GROUP BY SUBSTR(:B_FECHA, 4, 4) || SUBSTR(:B_FECHA, 1, 2), PROF.NOMBRE_PROFESION
    ORDER BY PROF.NOMBRE_PROFESION;

    COMMIT;
END;
/

SELECT * FROM DETALLE_ASIGNACION_MES;

SELECT * FROM RESUMEN_MES_PROFESION;

SELECT * FROM ERRORES_PROCESO ;
