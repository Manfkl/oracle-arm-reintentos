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
OCPUS="${OCPUS:-2}"         # 2 OCPU y 12 GB = todo el cupo gratuito de ARM
MEMORIA_GB="${MEMORIA_GB:-12}"

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

# 3. Intentar crearla.
echo "{\"ssh_authorized_keys\": \"$SSH_PUBLICA\"}" > metadata.json
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
codigo=$?

if [ $codigo -ne 0 ]; then
  if echo "$salida" | grep -qiE "Out of host capacity|Out of capacity|TooManyRequests|Too many requests|InternalError"; then
    echo "Oracle no tiene hueco ahora mismo. Se reintentará en el próximo turno."
    echo "$salida" | grep -iE '"message"|"code"' | head -3
    exit 0
  fi
  echo "Error inesperado al crear la máquina:"
  echo "$salida"
  exit 1
fi

ID="$salida"
echo "¡Máquina creada! ID: $ID"

# 4. Esperar a que arranque y leer la IP pública.
oci compute instance get --instance-id "$ID" --wait-for-state RUNNING --max-wait-seconds 600 > /dev/null || true
IP=$(oci compute instance list-vnics --instance-id "$ID" --query 'data[0]."public-ip"' --raw-output 2>/dev/null || echo "desconocida")
echo "IP pública: $IP"
echo "creada=true" >> "$GITHUB_OUTPUT"
echo "ip=$IP" >> "$GITHUB_OUTPUT"
