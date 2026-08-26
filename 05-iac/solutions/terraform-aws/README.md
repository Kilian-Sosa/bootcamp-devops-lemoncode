# Terraform AWS — solución IaC

> Solución del ejercicio de Infraestructura como Código (IaC) con Terraform
> sobre AWS para el módulo `05-iac` del bootcamp DevOps de Lemoncode.

---

## ⚠️ Estado real de la implementación

Esta solución está **implementada (escrita)** y validada solo de forma local.

- ✅ Implementación escrita: ficheros Terraform completos y revisados estáticamente.
- ✅ Validación local (26-08-2026): Terraform CLI 1.15.9; `terraform fmt
  -recursive`, `terraform init -backend=false` y `terraform validate` han
  finalizado correctamente en los dos directorios. `init` solo descargó
  proveedores/módulos del Registry y no configuró ningún backend ni contactó
  AWS.
- ❌ No se han creado recursos en AWS.
- ❌ No se ha ejecutado `terraform plan`, `terraform apply` ni `terraform destroy`.
- ❌ No hay evidencia de ejecución: **pendiente hasta que el usuario disponga de
  cuenta AWS**.

El agente que generó esta solución **no tiene cuenta AWS** y por acuerdo no debe
crear ni modificar recursos en la nube. Toda la evidencia de ejecución deberá
generarla el usuario una vez disponga de cuenta. **No se fabrican capturas ni
logs falsos.**

---

## Alcance

Esta solución cubre los 8 pasos del ejercicio:

| Paso | Descripción | Implementación |
|------|-------------|----------------|
| 1 | VPC con acceso a Internet (CIDR, región, IGW, asociación) | `01-manual-vpc` y `02-vpc-module` |
| 2 | Subred pública con ruta `0.0.0.0/0 -> IGW` y asociación | `01-manual-vpc` y `02-vpc-module` |
| 3 | Security Groups: HTTP 80 pública + SSH 22 solo desde la IP del usuario | `01-manual-vpc` y `02-vpc-module` |
| 4 | Key pair para SSH (importando clave pública local) | `01-manual-vpc` y `02-vpc-module` |
| 5 | Instancia EC2 Free-Tier (t3.micro) en la subred pública con IP pública | `01-manual-vpc` y `02-vpc-module` |
| 6 | `user_data` que instala Docker | `01-manual-vpc` y `02-vpc-module` |
| 7 | Output de la IP pública de la EC2 | `01-manual-vpc` y `02-vpc-module` |
| 8 | Refactor con `terraform-aws-modules/vpc/aws` | `02-vpc-module` |

- **`01-manual-vpc`** = pasos 1-7 implementados con recursos AWS nativos
  explícitos.
- **`02-vpc-module`** = paso 8 (refactor) reemplazando el cableado de red manual
  por el módulo oficial `terraform-aws-modules/vpc/aws` versión `6.6.1`.

---

## Estructura

```
05-iac/solutions/terraform-aws/
├── README.md
├── .gitignore
├── 01-manual-vpc/
│   ├── versions.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── network.tf
│   ├── security.tf
│   ├── key-pair.tf
│   ├── compute.tf
│   ├── outputs.tf
│   ├── user-data.sh
│   └── terraform.tfvars.example
└── 02-vpc-module/
    ├── versions.tf
    ├── provider.tf
    ├── variables.tf
    ├── locals.tf
    ├── network.tf
    ├── security.tf
    ├── key-pair.tf
    ├── compute.tf
    ├── outputs.tf
    ├── user-data.sh
    └── terraform.tfvars.example
```

No se ha modificado el material de formación bajo `05-iac/00-terraform/`.

---

## Seguridad y costes

- **`create_instance = false` por defecto**: en la Fase A (pasos 1-4) no se crea
  ninguna instancia EC2. Solo VPC, IGW, subred pública, tabla de rutas, SG y key
  pair.
- **Sin NAT Gateway**: el ejercicio usa IGW + subred pública. No se crea NAT
  Gateway ni Elastic IP. Una subred pública con IGW es suficiente.
- **HTTP 80 pública (`0.0.0.0/0`)**: requerido por el ejercicio para servir
  NGINX. Es deliberadamente abierto.
- **SSH 22 solo desde `/32` del usuario**: la variable `ssh_cidr` **no** abre al
  mundo. Por defecto `ssh_cidr = null` y, en ese caso, no se crea la regla SSH.
  Ejemplo: `203.0.113.10/32`.
- **La clave privada SSH nunca entra en el state de Terraform**: se importa una
  clave **pública** local con `file(pathexpand(var.ssh_public_key_path))`. No se
  usa `tls_private_key`.
- **Credenciales AWS fuera de Terraform**: no se guardan `access_key`,
  `secret_key` ni `session_token` en el código. Se usa la cadena estándar del
  provider AWS. No se recomiendan claves del usuario root.
- **EC2 y la IP pública IPv4 pueden tener coste**: para cuentas creadas después
  del 15 de julio de 2025 AWS usa su modelo más reciente de
  créditos/free-plan. **No se garantiza coste 0 €/0 $**. Confirma la elegibilidad
  Free Tier / los créditos de la cuenta antes de aplicar EC2.
- **`terraform destroy` siempre**: al terminar el ejercicio, destruye todo y
  verifica que no quedan instancias EC2 ni recursos facturables.

No se afirma que los recursos sean permanentemente gratis.

---

## Preparación futura

El usuario **no tiene cuenta AWS** todavía. Más adelante necesitará:

- **Cuenta AWS** (con MFA y usuario IAM, no usuario root).
- **Terraform** 1.x instalado localmente.
- **Credenciales AWS** mediante la cadena estándar del provider AWS
  (`AWS_PROFILE`, `~/.aws/credentials`, variables de entorno, SSO…). Configura
  las credenciales **fuera de Git/Terraform**. No uses claves del usuario root.
- **Clave SSH local**: genera una clave ED25519 con
  `ssh-keygen -t ed25519 -f ~/.ssh/lemoncode-iac` y registra la ruta de la clave
  **pública** en `ssh_public_key_path`. No subas la clave privada a ningún
  sitio.
- **IP pública actual en formato CIDR /32** para `ssh_cidr`, por ejemplo
  `203.0.113.10/32`.

> No ejecutes `ssh-keygen` si ya tienes una clave; este paso es
> documentación.

---

## Fase A — pasos 1-4

Objetivo: crear solo la infraestructura de red + SG + key pair, **sin EC2**.

Mantén:

```hcl
create_instance = false
```

Para una futura ejecución con una cuenta AWS, los comandos previstos son:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

> ⚠️ `terraform fmt`, `terraform init -backend=false` y `terraform validate`
> ya se ejecutaron localmente. `terraform plan` y `terraform apply` requieren
> una cuenta AWS y no se han ejecutado.

Recursos que deberían aparecer en la Fase A:

- VPC (CIDR `10.0.0.0/16`, DNS support + DNS hostnames activados).
- Internet Gateway asociado a la VPC.
- Subred pública (`10.0.1.0/24`) en una AZ dinámica,
  `map_public_ip_on_launch = true`.
- Tabla de rutas pública con ruta `0.0.0.0/0 -> IGW`, asociada a la subred.
- Security group: HTTP 80 desde `0.0.0.0/0` y **sin** regla SSH si
  `ssh_cidr = null`.
- Egress a `0.0.0.0/0` para permitir instalar Docker y descargar imágenes.
- Key pair importado desde la clave pública local.
- **Sin instancia EC2.**

---

## Fase B — pasos 5-7

Antes de cambiar `create_instance`:

1. Confirma la elegibilidad AWS Free Tier / los créditos de la cuenta (la EC2 y
   la IP pública IPv4 pueden tener coste).
2. Configura `ssh_cidr` con tu IP pública actual en formato `/32` (ej.
   `203.0.113.10/32`). Si `create_instance = true` **es obligatorio** que
   `ssh_cidr != null` (hay un `precondition` que lo garantiza).
3. Cambia a `create_instance = true`.
4. Revisa con `terraform plan` con cuidado.
5. `terraform apply`.
6. Lee la IP pública con `terraform output public_ip`.

Ejemplo futuro de SSH (Amazon Linux 2023), **documentación, no ejecutar ahora**:

```bash
ssh -i ~/.ssh/lemoncode-iac ec2-user@<PUBLIC_IP>
```

Paso manual del ejercicio (NGINX en Docker). El `user_data` **no** arranca NGINX
automáticamente: el alumno debe lanzarlo a mano por SSH:

```bash
docker run -d --name nginx -p 80:80 nginx:alpine
```

Luego:

```
http://<PUBLIC_IP>
```

> Documentación. No se ejecuta en esta solución.

---

## Docker `user_data`

`user-data.sh` es compatible con Amazon Linux 2023:

- instala Docker (`dnf install -y docker`);
- habilita e inicia el servicio `docker`;
- añade `ec2-user` al grupo `docker` para usar Docker sin `sudo`.

**NGINX no se arranca automáticamente** porque el ejercicio pide explícitamente
que el alumno, una vez conectado por SSH, lance el contenedor NGINX a mano.
Ese paso de aprendizaje se conserva deliberadamente.

---

## Fase C — paso 8

`02-vpc-module` reemplaza **solo el cableado de red** (VPC, IGW, subred, tabla de
rutas, ruta, asociación) por el módulo oficial:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"
  ...
}
```

El módulo `vpc` 6.6.1 requiere AWS provider `>= 6.28`. Ambas implementaciones
usan `~> 6.60`.

El security group, el key pair, el EC2 y el `user_data` **se mantienen** iguales
que en `01-manual-vpc` (salvo referencias a outputs del módulo). No se
duplican recursos de red manuales en `02-vpc-module`.

**No aplicar ambos directorios simultáneamente**: representan implementaciones
alternativas/evolutivas. Flujo recomendado:

1. Completa/valida `01-manual-vpc`.
2. `terraform destroy` (en `01-manual-vpc`).
3. Cambia a `02-vpc-module`.
4. `terraform apply` la implementación refactorizada.

No se sugiere migración de estado avanzada salvo que el ejercicio lo pida.

---

## Evidencia recomendada

A partir de los comentarios previos del profesor, una vez el usuario **ejecute**
el ejercicio, se sugieren estas capturas (**no crear capturas falsas**):

- `terraform plan` / `terraform apply` mostrando VPC/subred/ruta/SG/key pair
  (Fase A).
- Consola AWS: VPC / subred / tabla de rutas.
- Security group mostrando HTTP pública + SSH con el `/32` del usuario.
- EC2 en ejecución con su IP pública.
- Terminal con SSH correcto a la instancia.
- `docker ps` mostrando el contenedor `nginx`.
- Navegador mostrando la página de NGINX vía la IP pública de la EC2.
- `terraform destroy` final.

---

## Limpieza

**Obligatorio**: al terminar el ejercicio ejecuta

```bash
terraform destroy
```

y verifica en la consola AWS que **no quedan** instancias EC2, IP públicas
IPv4, VPC u otros recursos facturables. Recuerda que la IP pública IPv4 puede
generar coste aunque la instancia esté parada; por eso conviene destruir el
entorno por completo.
