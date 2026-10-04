# CONTEXTO — Configuración de Squid / PROXY

## 1. Instalación y respaldo

Se instaló Squid y se realizó un respaldo de la configuración original.

```bash
sudo apt update
sudo apt install squid

sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
```

Versión instalada: Squid 7.7 en Debian sid/forky.

---

## 2. Topología actual del PROXY

Topología general:

```text
ISP1/ISP2
    ↓
  R-EDGE
    ↓
    FW
    ↓
  PROXY
    ↓
    R2
    ↓
 VLANs
```

Direcciones del PROXY:

```text
enp0s31f6
10.10.0.6/30
FW → 10.10.0.5

enx9c69d3101d16
10.10.0.9/30
R2 → 10.10.0.10
```

Perfiles persistentes de NetworkManager:

```text
squid-firewall
squid-r2
```

Configuración:

```bash
sudo nmcli connection add type ethernet \
  ifname enp0s31f6 \
  con-name squid-firewall \
  ipv4.method manual \
  ipv4.addresses 10.10.0.6/30 \
  ipv4.never-default no \
  ipv6.method disabled

sudo nmcli connection add type ethernet \
  ifname enx9c69d3101d16 \
  con-name squid-r2 \
  ipv4.method manual \
  ipv4.addresses 10.10.0.9/30 \
  ipv4.never-default yes \
  ipv6.method disabled
```

Gateway y rutas:

```bash
sudo nmcli connection modify squid-firewall \
  ipv4.gateway 10.10.0.5 \
  ipv4.route-metric 100

sudo nmcli connection modify squid-r2 \
  +ipv4.routes "10.10.10.0/27 10.10.0.10" \
  +ipv4.routes "10.10.20.0/25 10.10.0.10" \
  +ipv4.routes "10.10.30.0/28 10.10.0.10" \
  +ipv4.routes "10.10.40.0/27 10.10.0.10"
```

Redes alcanzables a través de R2:

```text
10.10.10.0/27 → VLAN 10 Admin
10.10.20.0/25 → VLAN 20 Users
10.10.30.0/28 → VLAN 30 Zabbix
10.10.40.0/27 → VLAN 40 Servers
```

Las interfaces del proyecto se mantienen normalmente desconectadas mientras no exista conexión física con FW y R2. Esto evita modificar la salida a Internet del equipo durante el desarrollo.

El perfil antiguo `Wired connection 1` fue configurado para no realizar autoconexión:

```bash
sudo nmcli connection modify "Wired connection 1" connection.autoconnect no
```

---

## 3. ACL de redes y listas de bloqueo

En `/etc/squid/squid.conf`:

```text
acl admins src 10.10.10.0/27
acl users src 10.10.20.0/25

acl admins_blocked dstdomain "/etc/squid/admins_blacklist"
acl users_blocked dstdomain "/etc/squid/users_blacklist"
```

Archivos:

```text
/etc/squid/admins_blacklist
/etc/squid/users_blacklist
```

Actualmente contienen un dominio de prueba:

```text
.example.com
```

---

## 4. Reglas de acceso

En `/etc/squid/squid.conf`:

```text
http_access deny admins admins_blocked
http_access deny users users_blocked

http_access allow admins
http_access allow users

include /etc/squid/conf.d/*.conf

http_access deny all
```

La lógica es:

* Administradores: bloquean los dominios de `admins_blacklist` y permiten los demás.
* Usuarios: bloquean los dominios de `users_blacklist` y permiten los demás.
* Cualquier otra red: denegada.

---

## 5. Validación de Squid

La configuración actual fue validada con:

```bash
sudo squid -k parse
```

El parseo termina sin errores.

Los siguientes warnings pertenecen a `/etc/squid/conf.d/debian.conf`:

```text
WARNING: refresh_pattern maximum age too high. Cropped back to 1 year.
```

No afectan la configuración del proyecto.

---

## 6. Configuración de proxy e intercept

Squid utiliza:

```text
3128 → proxy explícito
3129 → proxy HTTP en modo intercept
```

Configuración:

```text
http_port 3128
http_port 3129 intercept
```

* `3128` → proxy convencional mediante configuración explícita del cliente.
* `3129` → recibe tráfico HTTP redirigido por R2.

Durante la integración, R2 deberá redirigir el tráfico TCP/80 de los clientes hacia:

```text
10.10.0.9:3129
```

No se configuró SSL Bump ni interceptación HTTPS.

La capacidad de intercept fue verificada mediante la configuración de Squid con soporte `--enable-linux-netfilter`.

---

## 7. Configuración de logging

Se utiliza un formato específico para el proyecto:

```text
logformat project %ts.%03tu %>a %Ss/%03>Hs %<st %rm %ru
access_log /var/log/squid/access.log project
```

El registro incluye:

* Timestamp.
* IP de origen.
* Estado de Squid.
* Cantidad de bytes.
* Método HTTP.
* URL solicitada.

Archivo:

```text
/var/log/squid/access.log
```

El usuario `debian` pertenece al grupo `proxy`, permitiendo al portal leer el log:

```bash
sudo usermod -aG proxy debian
```

Los permisos del log permiten lectura al grupo `proxy`.

La rotación está gestionada por Debian:

```text
/etc/logrotate.d/squid
```

La configuración realiza rotación diaria, compresión y conserva dos rotaciones anteriores.

---

## 8. Validación del logging

Se probó el proxy explícito mediante:

```bash
curl -x http://127.0.0.1:3128 http://example.com/ -o /dev/null
```

La solicitud quedó registrada en:

```text
/var/log/squid/access.log
```

Esta prueba valida el funcionamiento local de Squid y logging.

Las pruebas reales de las ACL de Administradores y Usuarios se realizarán durante la integración con las VLANs.

---

## 9. Portal administrativo Flask

Se creó un portal web para visualizar información básica de:

```text
/var/log/squid/access.log
```

Ubicación:

```text
/run/media/debian/01DAB4F382BBCF90/Users/Santizo/Desktop/U 2026/8vo Semestre/Cursos/Redes 2/Proyectos/Proyecto 2/squid-portal
```

El proyecto utiliza:

```text
.venv
```

El portal muestra:

* Número de solicitudes.
* Solicitudes permitidas.
* Solicitudes bloqueadas.
* Timestamp.
* IP de origen.
* Estado.
* Bytes.
* Método HTTP.
* URL.

Actualmente escucha en:

```text
0.0.0.0:8080
```

El acceso está restringido a la red de Administradores:

```text
10.10.10.0/27
```

Las conexiones locales (`127.0.0.1`) se permiten para administración y pruebas.

Las solicitudes provenientes de otras redes reciben:

```text
403 Forbidden
```

---

## 10. Servicio systemd del portal

Archivo:

```text
/etc/systemd/system/squid-portal.service
```

Configuración relevante:

```text
User=debian
Group=debian
SupplementaryGroups=proxy
```

Esto permite que el portal lea:

```text
/var/log/squid/access.log
```

El servicio no está habilitado para iniciar automáticamente:

```bash
systemctl is-enabled squid-portal
```

Resultado esperado:

```text
disabled
```

El servicio se ejecuta únicamente durante las pruebas o demostraciones.

---

## 11. Inicio y apagado temporal

Los servicios permanecen deshabilitados al arranque.

Para una demostración:

```bash
sudo systemctl start squid
sudo systemctl start squid-portal
```

Verificación:

```bash
sudo systemctl status squid --no-pager
sudo systemctl status squid-portal --no-pager
```

Al finalizar:

```bash
sudo systemctl stop squid-portal
sudo systemctl stop squid
```

Estado esperado:

```text
squid        → disabled
squid-portal → disabled
```

---

## 12. Integración pendiente

La configuración del PROXY está preparada. La integración física y funcional con los demás componentes queda pendiente.

Flujo:

```text
ISP1/ISP2
    ↓
  R-EDGE
    ↓
    FW
    ↓
  PROXY
    ↓
    R2
    ↓
 VLAN 10 / VLAN 20 / VLAN 30 / VLAN 40
```

Durante la integración se debe verificar:

* Conectividad PROXY ↔ FW.
* Conectividad PROXY ↔ R2.
* Rutas hacia las VLANs.
* Acceso al proxy desde VLAN 10 y VLAN 20.
* Redirección HTTP de R2 hacia `10.10.0.9:3129`.
* Bloqueo mediante `admins_blacklist`.
* Bloqueo mediante `users_blacklist`.
* Registro de solicitudes en `access.log`.
* Acceso al portal desde VLAN 10 mediante `10.10.0.6:8080` o la ruta correspondiente definida por el grupo.
* Funcionamiento de la salida hacia Internet.

El tráfico HTTPS no será interceptado mediante SSL Bump.

---

## 13. Verificación de integración

Cuando FW y R2 estén físicamente conectados, se podrán activar temporalmente las interfaces:

```bash
sudo nmcli connection up squid-firewall
sudo nmcli connection up squid-r2
```

Verificar:

```bash
ip -br addr show enp0s31f6 enx9c69d3101d16
ip route
```

Conectividad:

```bash
ping -c 4 10.10.0.5
ping -c 4 10.10.0.10
```

Iniciar servicios:

```bash
sudo systemctl start squid
sudo systemctl start squid-portal
```

Verificar puertos:

```bash
sudo ss -lntp | grep -E ':(3128|3129|8080)\b'
```

Validar Squid:

```bash
sudo squid -k parse
```

Revisar logs:

```bash
sudo tail -n 20 /var/log/squid/access.log
sudo tail -n 20 /var/log/squid/cache.log
```

Verificar portal:

```bash
curl -I http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/ | grep -E 'Solicitudes|Permitidas|Bloqueadas'
```

Al finalizar las pruebas:

```bash
sudo systemctl stop squid-portal
sudo systemctl stop squid
sudo nmcli connection down squid-firewall
sudo nmcli connection down squid-r2
```

Las pruebas anteriores deben realizarse únicamente cuando exista conexión física con los componentes correspondientes.
