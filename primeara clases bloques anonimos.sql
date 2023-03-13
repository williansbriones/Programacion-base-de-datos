declare 
    x_nombrecompleto VARCHAR2(50);
    x_estado NUMBER(1);
BEGIN
    ---imprimir estado y nombre
    select  
        nombre ||' '|| apellido,
        estado
    into 
        x_nombrecompleto,     
        x_estado
    from persona
    where
    ID = 1;
    
    DBMS_OUTPUT.PUT_LINE('NOMBRE' || xnombrecompleto);
    --print en el sql 
end;


create table persona (PRIMARY key nombrecompleto,
);