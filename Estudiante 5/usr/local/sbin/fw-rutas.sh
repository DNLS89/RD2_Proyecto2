#!/bin/bash
# FW: enrutamiento del tráfico reenviado.
# El tráfico que entra por la interfaz interna o por la DMZ usa primero la
# tabla principal sin su ruta por defecto (destinos internos) y, si no hay
# coincidencia, la tabla 100, cuya salida es R-EDGE. Así el tráfico propio del
# equipo puede seguir usando la Wi-Fi de gestión sin afectar al reenviado.
WAN=enp3s0
INSIDE=enx00e04c360188
DMZ=enx00e04c3604ff
REDGE=10.10.0.1

for pref in 100 101; do
  while ip rule del pref "$pref" 2>/dev/null; do :; done
done
for ifc in "$INSIDE" "$DMZ"; do
  ip rule add pref 100 iif "$ifc" lookup main suppress_prefixlength 0
  ip rule add pref 101 iif "$ifc" lookup 100
done
ip route replace default via "$REDGE" dev "$WAN" table 100 2>/dev/null || true
exit 0
