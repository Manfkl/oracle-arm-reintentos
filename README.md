# Reintentos para crear la máquina ARM gratuita de Oracle

Oracle Cloud a menudo responde «Out of capacity» al crear la máquina gratuita
`VM.Standard.A1.Flex` (ARM). Este repositorio lo reintenta **cada 10 minutos con GitHub Actions**,
así no hace falta tener el PC encendido.

- Pide la máquina ARM gratuita: primero con 2 OCPU y 12 GB y, si no hay hueco, con 1 OCPU y 6 GB (las dos dentro del plan *Always Free*).
- Cuando la consigue, **abre un issue con la IP pública** y se desactiva solo.
- Si Oracle no tiene hueco, no pasa nada: lo vuelve a intentar en el siguiente turno.
- Si aparece otro error, el workflow falla y GitHub te avisa por correo.

## Secrets necesarios (Settings → Secrets and variables → Actions)

| Secret | Qué es |
|---|---|
| `OCI_USER` | OCID del usuario |
| `OCI_TENANCY` | OCID de la tenancy (también se usa como compartimento) |
| `OCI_FINGERPRINT` | Huella de la clave API |
| `OCI_REGION` | `eu-madrid-1` |
| `OCI_KEY` | Clave privada de la API (contenido del `.pem`) |
| `OCI_SUBNET` | OCID de la subred pública |
| `SSH_PUBLICA` | Clave SSH pública para entrar en la máquina |

El código no contiene nada secreto: todos los datos de la cuenta están en los secrets.

## Al terminar

Borra la clave API en Oracle (*Mi perfil → Tokens and keys*) y archiva o borra este repositorio.
