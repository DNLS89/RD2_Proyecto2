# CONTEXTO — Configuración de Squid / PROXY

## 1. Instalación y respaldo

Se instaló Squid en Debian sid/forky y se respaldó la configuración original.

```bash
sudo apt update
sudo apt install squid
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
```

Versión instalada: Squid 7.7.

## 2. Topología y direccionamiento

```text
ISP1 / ISP2
     |
   R-EDGE
     |
     FW
     |
   PROXY
     |
     R2
     |
 VLAN 10 / VLAN 20 / VLAN 30 / VLAN 40
```

Interfaces del PROXY:

| Interfaz | Dirección | Conexión |
|---|---|---|
| `enp0s31f6` | `10.10.0.9/30` | R2 (`10.10.0.10`) |
| `enx00e04c3603e7` | `10.10.0.6/30` | FW (`10.10.0.5`) |

El adaptador USB-Ethernet hacia el firewall fue sustituido. La interfaz antigua era `enx9c69d3101d16`; la nueva es `enx00e04c3603e7`.

La interfaz `enp0s31f6` y el perfil `squid-r2` no cambiaron.

## 3. Configuración de NetworkManager

Perfiles existentes:

```text
squid-r2
squid-firewall
```

Creación original de los perfiles:

```bash
sudo nmcli connection add type ethernet \
  ifname enp0s31f6 \
  con-name squid-r2 \
  ipv4.method manual \
  ipv4.addresses 10.10.0.9/30 \
  ipv4.never-default yes \
  ipv6.method disabled

sudo nmcli connection add type ethernet \
  ifname enx9c69d3101d16 \
  con-name squid-firewall \
  ipv4.method manual \
  ipv4.addresses 10.10.0.6/30 \
  ipv4.never-default no \
  ipv6.method disabled
```

Configuración del gateway y las rutas originales:

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

### Cambio del adaptador hacia FW

Se actualizó el perfil existente `squid-firewall` para asociarlo a la interfaz nueva:

```bash
sudo nmcli connection modify squid-firewall \
  connection.interface-name enx00e04c3603e7

sudo nmcli connection up squid-firewall
```

El perfil conserva la dirección `10.10.0.6/30` y la configuración de enrutamiento.

Se comprobó el estado con:

```bash
nmcli device status
nmcli -f NAME,TYPE,DEVICE connection show

ip -br addr show enx00e04c3603e7
ip -4 route show table 101
ip -4 rule
```

La interfaz quedó activa con `10.10.0.6/30`. La tabla 101 mostró la ruta predeterminada vía `10.10.0.5`.

Redes alcanzables a través de R2:

```text
10.10.10.0/27 → VLAN 10 Admin
10.10.20.0/25 → VLAN 20 Users
10.10.30.0/28 → VLAN 30 Zabbix
10.10.40.0/27 → VLAN 40 Servers
```

Para revisar el estado de la red antes de activar TPROXY:

```bash
ip -br addr
ip -4 route
ip -4 rule show
nmcli connection show --active
```

El perfil `squid-r2` no debe instalar una ruta predeterminada. El perfil `squid-firewall` tiene configurada la salida por `10.10.0.5`.

El perfil antiguo `Wired connection 1` se configuró para no conectarse automáticamente:

```bash
sudo nmcli connection modify "Wired connection 1" connection.autoconnect no
```

## 4. Recuperación de conectividad y SSH

Después del cambio de adaptador, se recuperó la conexión entre el PROXY y el firewall.

Prueba realizada:

```bash
ping -c 3 10.10.0.5
```

Resultado: 3 paquetes enviados, 3 recibidos y 0 % de pérdida.

Se inició SSH y se comprobó que el servidor escucha en el puerto 22:

```bash
sudo systemctl start ssh
sudo systemctl status ssh --no-pager
sudo ss -lntp | grep ':22 '
```

La salida mostró `ssh.service` activo y `sshd` escuchando en `0.0.0.0:22` y `[::]:22`.

El acceso SSH con el usuario `soporte-fw` y su clave se probó. Desde la sesión remota se realizaron los cambios correspondientes a las referencias de la interfaz antigua en la configuración de TPROXY.

Para revisar el estado actual:

```bash
systemctl is-active ssh
systemctl is-enabled ssh
sudo ss -lntp | grep ':22 '
```

Si SSH continúa como `disabled`, habilitar el inicio automático:

```bash
sudo systemctl enable ssh
```


## 5. ACL y listas de bloqueo de Squid

Archivo principal:

```text
/etc/squid/squid.conf
```

ACL configuradas:

```text
acl admins src 10.10.10.0/27
acl users src 10.10.20.0/25

acl admins_blocked dstdomain "/etc/squid/admins_blacklist"
acl users_blocked dstdomain "/etc/squid/users_blacklist"
```

Archivos de listas:

```text
/etc/squid/admins_blacklist
/etc/squid/users_blacklist
```

Contenido de `admins_blacklist`:

```text
.ilovepdf.com
.facebook.com
.instagram.com
.tiktok.com
.x.com
```

Contenido de `users_blacklist`:

```text
.ilovepdf.com
.facebook.com
.instagram.com
.tiktok.com
.x.com
.youtube.com
.netflix.com
```

Las listas son independientes para aplicar políticas diferentes a Administración y Usuarios.

Reglas de acceso relevantes en `squid.conf`:

```text
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localhost
http_access deny to_localhost
http_access deny to_linklocal

http_access deny admins admins_blocked
http_access deny users users_blocked

http_access allow admins
http_access allow users

include /etc/squid/conf.d/*.conf
http_access deny all
```

Administración puede acceder a los dominios que no aparecen en su lista. Usuarios tienen restricciones adicionales. El resto de las redes queda denegado.

Para validar la configuración:

```bash
sudo squid -k parse
```

## 6. Puertos y TPROXY

Configuración relevante de `/etc/squid/squid.conf`:

```text
http_port 3128
http_port 3129 tproxy

tcp_outgoing_address 10.10.0.6
```

Función de cada directiva:

- `3128`: proxy explícito convencional.
- `3129 tproxy`: recibe el tráfico HTTP interceptado mediante TPROXY.
- `tcp_outgoing_address 10.10.0.6`: establece la dirección de origen de las conexiones salientes de Squid.

No hay SSL Bump, interceptación HTTPS ni filtrado SNI configurado.

Validación:

```bash
sudo squid -k parse
sudo ss -lntp | grep -E ':(3128|3129)\b'
```

## 7. Reglas nftables

Archivo del proyecto:

```text
/etc/nftables-xelajunetwork.nft
```

Regla de TPROXY:

```nft
table ip xelajunetwork_proxy {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname "enp0s31f6" ip saddr { 10.10.10.0/27, 10.10.20.0/25 } tcp dport 80 tproxy to :3129 meta mark set 0x1
    }
}
```

La regla selecciona el tráfico TCP/80 de VLAN 10 y VLAN 20 que ingresa por `enp0s31f6`. Lo dirige al puerto 3129 y marca los paquetes con `0x1`.

La interfaz de entrada sigue siendo `enp0s31f6`, porque el cambio de adaptador afectó únicamente al enlace hacia FW.

Validar sintaxis sin aplicar la tabla:

```bash
sudo nft -c -f /etc/nftables-xelajunetwork.nft
```

Consultar las reglas cargadas:

```bash
sudo nft list table ip xelajunetwork_proxy
```

La regla actual no contiene una exclusión explícita para destinos internos. Si se detecta que intercepta recursos internos, revisar el criterio de destino.

No ejecutar `nft flush ruleset` ni modificar `/etc/nftables.conf` sin revisar las reglas de Docker y Tailscale.

## 8. Enrutamiento por políticas

Tablas del proyecto:

```text
100 → xelajunetwork_tproxy
101 → salida por el firewall
```

Registro de la tabla 100 en `/etc/iproute2/rt_tables`:

```text
100 xelajunetwork_tproxy
```

El script crea una ruta local para los paquetes marcados y utiliza la tabla 101 para las conexiones con origen `10.10.0.6`.

La salida de `ip -4 rule` mostró reglas para las prioridades 1000, 1090 y 1100, entre otras. Hay reglas de prioridad 1090 y 1100 asociadas a NetworkManager, por lo que debe revisarse su interacción con las reglas del script antes de una nueva activación.

Comandos de diagnóstico:

```bash
ip -4 rule show
ip -4 route show table 100
ip -4 route show table 101
```

## 9. Scripts de activación y desactivación de TPROXY

Archivos:

```text
/usr/local/sbin/xelajunetwork-tproxy-on
/usr/local/sbin/xelajunetwork-tproxy-off
```

Ambos scripts se crearon con permisos `root:root`, modo `750`.

### Función de activación

El script `xelajunetwork-tproxy-on` comprueba las IP de las interfaces, crea las rutas de las tablas 100 y 101, agrega las reglas de política, carga la tabla nftables del proyecto e inicia Squid.

El script original contenía referencias a `enx9c69d3101d16`. Después del cambio de adaptador, se actualizaron las referencias correspondientes desde la sesión SSH para utilizar `enx00e04c3603e7`.

La interfaz hacia R2 sigue siendo `enp0s31f6`.

### Función de desactivación

El script `xelajunetwork-tproxy-off` elimina la tabla nftables del proyecto, las reglas de política 1000 y 1100, limpia las tablas de rutas 100 y 101 y detiene Squid.

No debe utilizarse sin considerar que detiene Squid, ya que el proxy explícito también dejará de funcionar mientras el servicio permanezca detenido.

### Validación de los scripts

```bash
sudo bash -n /usr/local/sbin/xelajunetwork-tproxy-on
sudo bash -n /usr/local/sbin/xelajunetwork-tproxy-off
```

Comprobar las referencias antiguas:

```bash
sudo grep -nH 'enx9c69d3101d16' \
  /usr/local/sbin/xelajunetwork-tproxy-on \
  /usr/local/sbin/xelajunetwork-tproxy-off \
  /etc/sysctl.d/90-xelajunetwork.conf
```

La salida esperada es vacía si todas las referencias fueron actualizadas.

Para revisar las referencias nuevas:

```bash
sudo grep -nH 'enx00e04c3603e7' \
  /usr/local/sbin/xelajunetwork-tproxy-on \
  /usr/local/sbin/xelajunetwork-tproxy-off \
  /etc/sysctl.d/90-xelajunetwork.conf
```


## 10. Persistencia y sysctl

Archivo:

```text
/etc/sysctl.d/90-xelajunetwork.conf
```

Este archivo contiene ajustes relacionados con el funcionamiento de TPROXY, incluido `accept_local`.

La referencia a la interfaz antigua se actualizó después del cambio de adaptador. Para aplicar los valores configurados:

```bash
sudo sysctl --system
```

Consultar los valores relevantes:

```bash
sysctl net.ipv4.conf.all.accept_local
sysctl net.ipv4.conf.default.accept_local
```

Revisar también los valores de la interfaz concreta cuando sea necesario:

```bash
sysctl net.ipv4.conf.enp0s31f6.accept_local
sysctl net.ipv4.conf.enx00e04c3603e7.accept_local
```

No modificar los valores sin revisar el diseño de TPROXY y la configuración persistente.

El archivo `/etc/nftables.conf` contiene una configuración base con `flush ruleset`. El servicio `nftables` está habilitado y activo.

## 11. Consideraciones de Multi-WAN y NAT

Squid genera conexiones salientes propias. La configuración utiliza `10.10.0.6` como dirección de origen y el script dirige ese tráfico mediante la tabla 101, con gateway `10.10.0.5`.

Las conexiones salientes de Squid no conservan automáticamente la IP original del cliente como dirección de origen. Esto debe considerarse en las políticas de Multi-WAN y en los registros del firewall.

No se ha configurado NAT/MASQUERADE en el PROXY.

La regla TPROXY selecciona tráfico HTTP TCP/80.

## 12. Logging de Squid

Formato configurado en `/etc/squid/squid.conf`:

```text
logformat project %ts.%03tu %>a %Ss/%03>Hs %<st %rm %ru
access_log /var/log/squid/access.log project
```

El log registra timestamp, IP de origen observada por Squid, estado, código HTTP, bytes, método y URL.

Archivo principal:

```text
/var/log/squid/access.log
```

El usuario `debian` pertenece al grupo `proxy`:

```bash
sudo usermod -aG proxy debian
```

Si el grupo se agregó recientemente, es necesario abrir una nueva sesión para que se actualicen los grupos del usuario.

La rotación se configura en:

```text
/etc/logrotate.d/squid
```

Se configuró rotación diaria, compresión y conservación de dos rotaciones anteriores.

Prueba del proxy explícito local:

```bash
curl -x http://127.0.0.1:3128 http://example.com/ -o /dev/null
```

La solicitud quedó registrada en `access.log`. Esta prueba valida el proxy explícito y el logging, pero no valida por sí sola TPROXY ni las ACL aplicadas a las VLAN.

Consultar los logs:

```bash
sudo tail -n 20 /var/log/squid/access.log
sudo tail -n 20 /var/log/squid/cache.log
```

## 13. Portal administrativo Flask

Ubicación del proyecto:

```text
/run/media/debian/01DAB4F382BBCF90/Users/Santizo/Desktop/U 2026/8vo Semestre/Cursos/Redes 2/Proyectos/Proyecto 2/squid-portal
```

El proyecto utiliza el entorno virtual `.venv` y muestra estadísticas extraídas de:

```text
/var/log/squid/access.log
```

Información mostrada:

- Número de solicitudes.
- Solicitudes permitidas y bloqueadas.
- Timestamp.
- IP de origen.
- Estado.
- Bytes.
- Método HTTP.
- URL.

El portal escucha en `0.0.0.0:8080`.

La dirección configurada para acceder al portal desde la red de Administración es:

```text
http://10.10.0.6:8080/
```


## 14. Servicio systemd del portal

Archivo:

```text
/etc/systemd/system/squid-portal.service
```

Configuración relevante:

```ini
User=debian
Group=debian
SupplementaryGroups=proxy
```

Esto permite que el portal lea los logs de Squid.

El servicio está diseñado para iniciarse manualmente durante las pruebas:

```bash
systemctl is-enabled squid-portal
systemctl status squid-portal --no-pager
```

Si no inicia:

```bash
sudo journalctl -u squid-portal -n 50 --no-pager
```

Para iniciarlo:

```bash
sudo systemctl start squid-portal
```

Para detenerlo:

```bash
sudo systemctl stop squid-portal
```

## 15. Comandos de integración

### Antes de activar TPROXY

Verificar las interfaces y las rutas:

```bash
nmcli device status
ip -br addr show enp0s31f6
ip -br addr show enx00e04c3603e7
ip -4 route
ip -4 rule show
```

Comprobar la conectividad:

```bash
ping -c 4 10.10.0.5
ping -c 4 10.10.0.10
```


### Activar TPROXY

Solo cuando el PROXY esté conectado físicamente a FW y R2:

```bash
sudo /usr/local/sbin/xelajunetwork-tproxy-on
```

### Iniciar el portal

```bash
sudo systemctl start squid-portal
```

### Verificar servicios y puertos

```bash
systemctl status squid --no-pager
systemctl status squid-portal --no-pager

sudo ss -lntp | grep -E ':(3128|3129|8080)\b'
sudo squid -k parse
```

### Verificar nftables y las rutas

```bash
sudo nft list table ip xelajunetwork_proxy
ip -4 rule show
ip -4 route show table 100
ip -4 route show table 101
```

### Verificar el portal localmente

```bash
curl -I http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/ | grep -E 'Solicitudes|Permitidas|Bloqueadas'
```

### Revisar logs

```bash
sudo tail -n 20 /var/log/squid/access.log
sudo tail -n 20 /var/log/squid/cache.log
```

### Desactivar TPROXY al terminar

```bash
sudo systemctl stop squid-portal
sudo /usr/local/sbin/xelajunetwork-tproxy-off
```

Verificar el estado:

```bash
systemctl is-active squid
systemctl is-active squid-portal
ip -4 rule show
```


## 16. Pruebas de las ACL desde los clientes

Desde PC-USER01, en VLAN 20:

```bash
curl -sS -m 12 -o /dev/null -w 'HTTP=%{http_code}\n' -I http://www.youtube.com
```

Se espera un `403` si la solicitud llega a Squid y coincide con la blacklist de Usuarios.

Desde PC-ADMIN01, en VLAN 10:

```bash
curl -sS -m 12 -o /dev/null -w 'HTTP=%{http_code}\n' -I http://www.youtube.com
```

Se espera un código distinto de `403` si el dominio no está bloqueado para Administración y la solicitud llega correctamente al destino.

Para probar cambios dinámicos en `users_blacklist`, primero respaldar la lista y comprobar que el dominio de prueba no exista ya en ella.

En el PROXY:

```bash
sudo cp -a /etc/squid/users_blacklist /tmp/users_blacklist.bak
grep -nF '.example.net' /etc/squid/users_blacklist
```

Si el dominio no aparece, añadirlo y recargar la configuración sin reiniciar el servicio:

```bash
echo '.example.net' | sudo tee -a /etc/squid/users_blacklist
sudo squid -k parse && sudo squid -k reconfigure
```

Repetir la solicitud desde PC-USER01. Si coincide con la regla, se espera un `403`.

Restaurar la lista original:

```bash
sudo cp -a /tmp/users_blacklist.bak /etc/squid/users_blacklist
sudo squid -k parse && sudo squid -k reconfigure
```

Repetir la prueba para confirmar que el acceso vuelve a estar permitido.

## 17. Estado actual y pendientes

### Cambios realizados y comprobados

```text
Squid 7.7                   → instalado
ACL Admin/Users             → configuradas
Blacklists                  → configuradas
Puerto 3128                 → proxy explícito
Puerto 3129                 → TPROXY
tcp_outgoing_address        → 10.10.0.6
Logging                     → configurado
Portal Flask 8080           → configurado
Perfil squid-r2             → conservado
Perfil squid-firewall       → actualizado
Interfaz hacia R2           → enp0s31f6
Interfaz nueva hacia FW     → enx00e04c3603e7
IP del enlace hacia FW      → 10.10.0.6/30
Ping a FW                   → comprobado, 0 % de pérdida
Servidor SSH                → activo y puerto 22 escuchando
Acceso SSH                  → probado
Referencias de TPROXY       → cambios realizados desde SSH
NAT/MASQUERADE en PROXY     → no configurado
SSL Bump                    → no configurado
Interceptación HTTPS        → no configurada
```

### Pendiente de verificar

```text
Validación de scripts TPROXY después del cambio
Referencias antiguas restantes en los archivos
Interacción entre las reglas de NetworkManager y las del script
Inicio automático de SSH
Conectividad PROXY ↔ R2
Interceptación HTTP desde VLAN 10 y VLAN 20
ACL y blacklists durante la integración
Logging desde las VLAN
Acceso al portal desde Administración
Tráfico no HTTP
Salida a Internet y funcionamiento conjunto con Multi-WAN
```

