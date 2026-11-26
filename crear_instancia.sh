#!/usr/bin/env bash
# Intenta crear la máquina ARM gratuita de Oracle (VM.Standard.A1.Flex).
#
# Lo ejecuta GitHub Actions cada 10 minutos. Posibles resultados:
#   - Ya existe la máquina      -> avisa y desactiva el workflow.
#   - Oracle no tiene hueco     -> termina bien (exit 0) y se reintenta en el siguiente turno.
#   - Se ha creado              -> espera la IP pública, abre un issue con ella y desactiva el workflow.
#   - Cualquier otro error      -> falla (exit 1) y GitHub te manda un correo.
#
# Los datos de la cuenta llegan como variables de entorno (secrets del repositorio).
set -uo pipefail

NOMBRE="bot-musica"
FORMA="VM.Standard.A1.Flex"
# Tamaños que se prueban, en orden: primero todo el cupo gratuito (2 OCPU, 12 GB)
# y, si no hay hueco, la mitad (1 OCPU, 6 GB), que es más fácil de conseguir
# y al bot le sobra. Los dos son gratis.
TAMANOS=("2 12" "1 6")

oci() { command oci "$@"; }

# 1. ¿Ya existe una máquina con ese nombre (que no esté borrada)?
existentes=$(oci compute instance list -c "$OCI_TENANCY" --display-name "$NOMBRE" \
  --query 'data[?"lifecycle-state"!=`TERMINATED` && "lifecycle-state"!=`TERMINATING`] | length(@)' --raw-output 2>/dev/null || echo 0)
if [ "${existentes:-0}" != "0" ] && [ -n "$existentes" ]; then
  echo "Ya existe la máquina $NOMBRE. No hago nada."
  echo "ya_existe=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

# 2. Datos que necesita Oracle: dominio de disponibilidad e imagen de Ubuntu 24.04 ARM más reciente.
AD=$(oci iam availability-domain list -c "$OCI_TENANCY" --query 'data[0].name' --raw-output)
IMAGEN=$(oci compute image list -c "$OCI_TENANCY" --operating-system "Canonical Ubuntu" \
  --operating-system-version "24.04" --shape "$FORMA" --sort-by TIMECREATED \
  --query 'data[0].id' --raw-output)
echo "Dominio: $AD"
echo "Imagen:  $IMAGEN"

# 3. Intentar crearla con cada tamaño, de mayor a menor.
echo "{\"ssh_authorized_keys\": \"$SSH_PUBLICA\"}" > metadata.json
ID=""
for tamano in "${TAMANOS[@]}"; do
  read -r OCPUS MEMORIA_GB <<< "$tamano"
  echo "Probando $OCPUS OCPU y $MEMORIA_GB GB…"
  salida=$(oci compute instance launch \
    --compartment-id "$OCI_TENANCY" \
    --availability-domain "$AD" \
    --display-name "$NOMBRE" \
    --shape "$FORMA" \
    --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORIA_GB}" \
    --image-id "$IMAGEN" \
    --subnet-id "$OCI_SUBNET" \
    --assign-public-ip true \
    --metadata file://metadata.json \
    --query 'data.id' --raw-output 2>&1)
  if [ $? -eq 0 ]; then
    ID="$salida"
    break
  fi
  if echo "$salida" | grep -qiE "Out of host capacity|Out of capacity|TooManyRequests|Too many requests|InternalError"; then
    echo "  Sin hueco para este tamaño."
    echo "$salida" | grep -iE '"message"' | head -1
    sleep 5
    continue
  fi
  echo "Error inesperado al crear la máquina:"
  echo "$salida"
  exit 1
done

if [ -z "$ID" ]; then
  echo "Oracle no tiene hueco ahora mismo. Se reintentará en el próximo turno."
  exit 0
fi

echo "¡Máquina creada con $OCPUS OCPU y $MEMORIA_GB GB! ID: $ID"
echo "tamano=$OCPUS OCPU y $MEMORIA_GB GB" >> "$GITHUB_OUTPUT"

# 4. Esperar a que arranque y leer la IP pública.
oci compute instance get --instance-id "$ID" --wait-for-state RUNNING --max-wait-seconds 600 > /dev/null || true
IP=$(oci compute instance list-vnics --instance-id "$ID" --query 'data[0]."public-ip"' --raw-output 2>/dev/null || echo "desconocida")
echo "IP pública: $IP"
echo "creada=true" >> "$GITHUB_OUTPUT"
echo "ip=$IP" >> "$GITHUB_OUTPUT"
