ALTER SESSION SET NLS_TERRITORY = 'Chile';
var fecha NVARCHAR2;
var usuario NVARCHAR2;
var max_desc number;
exec :fecha := '202106';
exec :max_desc := 50000;
exec :usuario := 'WilliansB';
declare 
-----------------declaracion de los cursores 
cursor c_pedidos (id_cep number,fech varchar2) is select -------cursor principal que almacena los datos fundamentales para los calculos
c.nom_cepa,
sum(dp.subtotal),
0 as gravamen,
count(*),
to_char(p.fec_pedido,'dd/mm/yyyy'),
0  as descuento_cepa,
0  as Monto_delivery
from pedido p
join detalle_pedido dp on (dp.id_pedido = p.id_pedido)
join producto pr on (pr.id_producto = dp.id_producto)
join cepa c on (c.id_cepa = pr.id_cepa)
where to_char(p.fec_pedido,'yyyymm') = fech and c.id_cepa = id_cep
group by c.nom_cepa, to_char(p.fec_pedido,'dd/mm/yyyy')
order by to_char(p.fec_pedido,'dd/mm/yyyy')
;
cursor c_cepa is select nom_cepa, id_cepa from cepa order by nom_cepa;--cursor para obtener todas las cepas permitiendo iterar las que no tienen pedidos en el mes
-----------------------creacion de records
type r_total_x_cepa is record(  -------record en el que almacenare todos los elemento que requiere la tabla RESUMEN_VENTAS_CEPA
    nom_cepa            cepa.NOM_CEPA%TYPE,--?
    num_pedidos         RESUMEN_VENTAS_CEPA.NUM_PEDIDOS%type,--?
    monto_pedidos       RESUMEN_VENTAS_CEPA.MONTO_PEDIDOS%type,--?
    gravamenes          RESUMEN_VENTAS_CEPA.GRAVAMENES%type,--?
    DESCTOS_CEPA        RESUMEN_VENTAS_CEPA.DESCTOS_CEPA%type,--?
    Monto_delivery      RESUMEN_VENTAS_CEPA.MONTO_DELIVERY%type,--?
    MONTO_DESCUENTOS    RESUMEN_VENTAS_CEPA.MONTO_DESCUENTOS%type,--?
    total               RESUMEN_VENTAS_CEPA.TOTAL_RECAUDACION %type --?
);
type r_p_indiv is record(  ------------record que almacenara los datos individuales de los pedidos, este select trabajara direcctamente con el cursor c_pedidos
    nom_cepa        cepa.NOM_CEPA%TYPE,
    sub_total       number,
    gravamen        number,
    cantidad        number,
    fecha           varchar(20),
    decuento_cepa   number,
    Monto_delivery  number
);
type r_error is record(  ------------record que almacena los valores de los errores para almacenarlos en la tabla ERRORES_PROCESO_RECAUDACION
    id_error ERRORES_PROCESO_RECAUDACION.ERROR_ID%type,
    ore_msg  ERRORES_PROCESO_RECAUDACION.ORA_MSG%type,
    usr_msg  ERRORES_PROCESO_RECAUDACION.USR_MSG%type
);
------------------------creacion de una array
type v_id_cepa is varray(4) of number(10);   ----array que almacenara los id de las cepas que tienen un descuento
type v_decuento_cepa is varray(5) of number(10); --array que almacenra los porcentajes de descuento por cepa
type v_delvery is varray(1) of number(10);
------------------------creacion de una excepcion
Sobre_el_limite     EXCEPTION;
------------------------creacion de variables
v_pedidos           r_total_x_cepa;
v_p_indiv           r_p_indiv;
v_error             r_error;
gravamen_porc       number;
gravamen_acum       number;
descuento_cepa_acum number;
acumulador_delivey number;
v_array_id_cepa     v_id_cepa := v_id_cepa(3,5,4,2);  --poblando array
v_array_desc_cepa   v_decuento_cepa := v_decuento_cepa(23,21,19,17,15); --poblando array
V_array_delivety    v_delvery := v_delvery(1800);--poblando array
-----------------------programacion del algoritmo para poblar la tabla RESUMEN_VENTAS_CEPA
begin
------------aqui se truncaron las tablas y se receteo el select correspondiente
    execute immediate 'TRUNCATE TABLE RESUMEN_VENTAS_CEPA';
    execute immediate 'TRUNCATE TABLE ERRORES_PROCESO_RECAUDACION';
    execute immediate 'drop SEQUENCE sq_error';
    execute immediate 'create SEQUENCE sq_error';
---------------inicio del primer loop que iterara los tipod de cepa 
    for for_cepa in c_cepa loop
-------------------------------------------limpieza de las variables de las cepas
        v_pedidos.nom_cepa := for_cepa.nom_cepa;
        v_pedidos.monto_pedidos := 0;
        v_pedidos.num_pedidos   := 0;
        v_pedidos.gravamenes    := 0;
        v_pedidos.DESCTOS_CEPA  := 0;
        v_pedidos.Monto_delivery:= 0;
        v_pedidos.MONTO_DESCUENTOS := 0;
        v_pedidos.total := 0;
-------------------------------------------Limpieza de las variables acumuladoras
        gravamen_acum           :=0;
        descuento_cepa_acum     :=0;
        acumulador_delivey      :=0;
-------------------------------------------Cursor c_pedidos abierto para seleccionar pedidos por tipos de cepas y la fecha de ejecucion
        open c_pedidos(for_cepa.id_cepa, :fecha);
        begin 
            -----------------------sendo loop en donde consultara a los pedidos por dia individuales, sumandolos segun la sepa
            loop
                fetch c_pedidos into v_p_indiv; -----insersion de datos al record v_p_indiv
                exit when c_pedidos%notfound;   -----una vez que el cursor no tenga datos cierra el ciclo
                v_pedidos.monto_pedidos := v_p_indiv.sub_total + v_pedidos.monto_pedidos;---calculo de monto total mensual por cepa donde se suman los pedidos por fecha
                
                begin ----------------calculo de gravamen por pedido individual
                    gravamen_porc := 0;
                    select 
                    PCTGRAVAMEN 
                    into 
                    gravamen_porc
                    from gravamen where v_p_indiv.sub_total BETWEEN MTO_VENTA_INF and MTO_VENTA_SUP;
                        v_p_indiv.gravamen :=  round(v_p_indiv.sub_total* (gravamen_porc/100));
                        gravamen_acum := v_p_indiv.gravamen + gravamen_acum;
                        v_pedidos.num_pedidos := v_pedidos.num_pedidos + v_p_indiv.cantidad;
                        exception  ---exceptions segun cual sea el caso de error para los callculos de gravamen
                            when NO_DATA_FOUND then
                            v_pedidos.num_pedidos := v_pedidos.num_pedidos + v_p_indiv.cantidad;
                            v_error.id_error := SQ_error.nextval;
                            v_error.ore_msg := SQLERRM;
                            v_error.usr_msg := :usuario||': No se encontró porcentaje de gravamen para el monto de los pedidos del dia '|| v_p_indiv.fecha;
                            insert into ERRORES_PROCESO_RECAUDACION values v_error;
                            commit;
                            when others then
                            v_pedidos.num_pedidos := v_pedidos.num_pedidos + v_p_indiv.cantidad;
                            v_error.id_error := SQ_error.nextval;
                            v_error.ore_msg := SQLERRM;
                            v_error.usr_msg := :usuario||': Se encontró más de un porcentaje de gravamen para el monto de los pedidos del dia '|| v_p_indiv.fecha;
                            insert into ERRORES_PROCESO_RECAUDACION values v_error;
                            commit;
                end;
                begin       ----calculo de descuento por cepa segun corresponda 
                    if(for_cepa.id_cepa = v_array_id_cepa(1)) then -------cepa numero 3
                        v_p_indiv.decuento_cepa := round(v_p_indiv.sub_total * (v_array_desc_cepa(1)/100));
                            if(v_p_indiv.decuento_cepa >:max_desc) then
                                raise Sobre_el_limite;
                            end if;
                        descuento_cepa_acum := descuento_cepa_acum + v_p_indiv.decuento_cepa;
                    elsif (for_cepa.id_cepa = v_array_id_cepa(2)) then -------cepa numero 5
                        v_p_indiv.decuento_cepa := round(v_p_indiv.sub_total * (v_array_desc_cepa(2)/100));
                            if(v_p_indiv.decuento_cepa >:max_desc) then
                                raise Sobre_el_limite;
                            end if;
                        descuento_cepa_acum := descuento_cepa_acum + v_p_indiv.decuento_cepa;
                    elsif (for_cepa.id_cepa = v_array_id_cepa(3)) then -------cepa numero 4
                        v_p_indiv.decuento_cepa := round(v_p_indiv.sub_total * (v_array_desc_cepa(3)/100));
                            if(v_p_indiv.decuento_cepa >:max_desc) then
                                raise Sobre_el_limite;
                            end if;
                        descuento_cepa_acum := descuento_cepa_acum + v_p_indiv.decuento_cepa;
                    elsif (for_cepa.id_cepa = v_array_id_cepa(4)) then -------cepa numero 2
                        v_p_indiv.decuento_cepa := round(v_p_indiv.sub_total * (v_array_desc_cepa(4)/100));
                            if(v_p_indiv.decuento_cepa >:max_desc) then
                                raise Sobre_el_limite;
                            end if;
                        descuento_cepa_acum := descuento_cepa_acum + v_p_indiv.decuento_cepa;
                    else
                        v_p_indiv.decuento_cepa := round(v_p_indiv.sub_total * (v_array_desc_cepa(5)/100));
                            if(v_p_indiv.decuento_cepa >:max_desc) then
                                raise Sobre_el_limite;
                            end if;
                        descuento_cepa_acum := descuento_cepa_acum + v_p_indiv.decuento_cepa;
                    end if;
                    exception  ----------exception en caso de que el calculo de descuento supere las 50.000
                    when Sobre_el_limite then
                    v_error.id_error := SQ_error.nextval;
                    v_error.ore_msg := 'ORA-20001: Monto de comisión sobrepasó el límite permitido';
                    v_error.usr_msg := :usuario||': Se reemplazó el monto de comisión calculada de '|| to_char(v_p_indiv.decuento_cepa, 'Fml999g999g999') 
                    || ' por el monto límite de '||to_char(:max_desc, 'Fml999g999g999');
                    insert into ERRORES_PROCESO_RECAUDACION values v_error;
                    commit;
                    v_p_indiv.decuento_cepa :=:max_desc;
                    descuento_cepa_acum := descuento_cepa_acum + v_p_indiv.decuento_cepa;
                end;
                begin  ----calculo de del cargo por delivery
                    v_p_indiv.Monto_delivery := V_array_delivety(1) * v_p_indiv.cantidad;
                    acumulador_delivey := acumulador_delivey + v_p_indiv.Monto_delivery;
                end;
                begin  ---Estructura donde se volcaran los valores de las variables para darle un valor a al record v_pedido
                    v_pedidos.gravamenes := gravamen_acum;
                    v_pedidos.DESCTOS_CEPA := descuento_cepa_acum;
                    v_pedidos.Monto_delivery:= acumulador_delivey;
                    v_pedidos.MONTO_DESCUENTOS := v_pedidos.Monto_delivery + v_pedidos.DESCTOS_CEPA + v_pedidos.gravamenes;
                    v_pedidos.total := v_pedidos.monto_pedidos-v_pedidos.MONTO_DESCUENTOS;
                end;
            end loop;
            exception --exception en el dado caso de la cepa no tenga ventas en el mes los valores se setiaran en 0 
                when NO_DATA_FOUND then
                v_pedidos.monto_pedidos := 0;
                v_pedidos.num_pedidos := 0;
                v_pedidos.gravamenes :=0;
                v_pedidos.DESCTOS_CEPA  := 0;
                v_pedidos.Monto_delivery:= 0;
                v_pedidos.MONTO_DESCUENTOS := 0;
                v_pedidos.total := 0;
        end;
        close c_pedidos;----cierre del cursor, para dar paso al siguiente tipo de sepa segin sea el caso
        Insert into RESUMEN_VENTAS_CEPA values v_pedidos; -- insercion del record v_pedidos en la tabla RESUMEN_VENTAS_CEPA
        commit;
---------------------------valores que se muestan por la salida dbms para debuguear valor segun sea el caso
        dbms_output.put_line('nombre cepa: '||  v_pedidos.nom_cepa);
        dbms_output.put_line('monto_pedidos: '||  v_pedidos.monto_pedidos);
        dbms_output.put_line('cantidad de pedidos: '||v_pedidos.num_pedidos);
        dbms_output.put_line('total gravamenes: '||v_pedidos.gravamenes);
        dbms_output.put_line('cantidad de desuento cepa: '||v_pedidos.DESCTOS_CEPA);
        dbms_output.put_line('monto delivery: '||v_pedidos.Monto_delivery);
        dbms_output.put_line('decuentos totales: '||v_pedidos.MONTO_DESCUENTOS);
        dbms_output.put_line('Total : '||v_pedidos.total);        
        dbms_output.put_line('------------------------------');
    end loop;
    dbms_output.put_line('script corriendo ???');
end;