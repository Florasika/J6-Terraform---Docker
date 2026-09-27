# 🏗️ Jour 6 / 10 — Terraform : Terraform & Docker

> **Série : 10 Days of Terraform** · Jour 6/10  
> Concepts : Provider Docker · docker_container · docker_network · docker_volume · Variables injectées

---

## 📁 Fichiers du projet

```
day-06-terraform-docker/
│
├── main.tf              ← Réseau + Images + Conteneurs + Volume
├── variables.tf         ← Variables
├── outputs.tf           ← Connexion BDD, noms des conteneurs
├── app/
│   └── pipeline.py      ← Script ETL monté dans le conteneur ETL
├── output/              ← Fichiers CSV générés (bind mount)
└── README.md
```

---

## 🧠 Terraform + Docker — pourquoi ?

```
Avant : docker-compose.yml écrit manuellement
Après : Terraform crée les conteneurs, réseaux, volumes

Avantages :
→ State Terraform = savoir exactement ce qui tourne
→ Variables Terraform injectées dans les conteneurs
→ Même workflow : plan → apply → destroy
→ Intégrable dans un pipeline CI/CD existant
```

---

## 🚀 ÉTAPE 1 — Prérequis

```bash
# Docker doit être installé et en cours d'exécution
docker --version
docker ps   # doit fonctionner sans erreur

# Installer le provider Terraform Docker (automatique via init)
# Source : kreuzwerker/docker
```

---

## 🚀 ÉTAPE 2 — Préparer les fichiers

```bash
mkdir -p jour6-terraform/app
mkdir -p jour6-terraform/output
cd jour6-terraform/

# Copier les fichiers :
# main_j6.tf      → main.tf
# variables_j6.tf → variables.tf
# outputs_j6.tf   → outputs.tf
# pipeline_j6.py  → app/pipeline.py

cat > .gitignore << 'EOF'
.terraform/
.terraform.lock.hcl
terraform.tfstate*
output/
EOF
```

---

## 🔑 ÉTAPE 3 — Le provider Docker

```hcl
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"   # Linux/Mac
  # Windows : "npipe:////.//pipe//docker_engine"
}
```

---

## 🔑 ÉTAPE 4 — Resources Docker dans Terraform

### Réseau
```hcl
resource "docker_network" "etl_network" {
  name   = "etl-dev-net"
  driver = "bridge"
}
```

### Image (pull)
```hcl
resource "docker_image" "postgres" {
  name         = "postgres:15-alpine"
  keep_locally = true   # ne pas supprimer au terraform destroy
}
```

### Volume persistant
```hcl
resource "docker_volume" "pgdata" {
  name = "etl-dev-pgdata"
}
```

### Conteneur PostgreSQL
```hcl
resource "docker_container" "postgres" {
  name  = "etl-dev-postgres"
  image = docker_image.postgres.image_id

  env = [
    "POSTGRES_DB=etl_portfolio_dev",
    "POSTGRES_USER=admin",
    "POSTGRES_PASSWORD=${random_password.db_password.result}",
  ]

  ports {
    internal = 5432
    external = 5432
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = docker_network.etl_network.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U admin"]
    interval = "10s"
    retries  = 5
  }
}
```

### Conteneur ETL avec variables injectées
```hcl
resource "docker_container" "etl" {
  name  = "etl-dev-etl"
  image = docker_image.python.image_id

  command = ["sh", "-c",
    "pip install -q pandas psycopg2-binary sqlalchemy && python /app/pipeline.py"
  ]

  # Variables injectées par Terraform → disponibles dans pipeline.py
  env = [
    "DB_HOST=etl-dev-postgres",   # nom du conteneur postgres
    "DB_PASSWORD=${random_password.db_password.result}",
    "PROJET=${var.nom_projet}",
  ]

  # Monter le script pipeline depuis l'hôte
  volumes {
    host_path      = abspath("${path.module}/app")
    container_path = "/app"
    read_only      = true
  }

  depends_on = [docker_container.postgres]
}
```

---

## 🚀 ÉTAPE 5 — Initialiser et appliquer

```bash
# Init — télécharge le provider kreuzwerker/docker
terraform init

# Plan — voir ce qui va être créé
terraform plan

# Résultat :
# docker_network.etl_network      will be created
# docker_volume.pgdata            will be created
# docker_image.postgres           will be created
# docker_image.python             will be created
# random_password.db_password     will be created
# docker_container.postgres       will be created
# docker_container.etl            will be created
# local_file.docker_config        will be created
# Plan: 8 to add, 0 to change, 0 to destroy.

# Appliquer
terraform apply -auto-approve
```

---

## 🚀 ÉTAPE 6 — Vérifier les conteneurs

```bash
# Voir les conteneurs créés par Terraform
docker ps
# etl-dev-postgres   postgres:15-alpine  Up (healthy)
# etl-dev-etl        python:3.11-slim    Up

# Voir les logs du pipeline ETL
docker logs etl-dev-etl

# Voir le réseau créé
docker network ls | grep etl

# Voir le volume créé
docker volume ls | grep etl

# Vérifier les données en base
docker exec etl-dev-postgres psql -U admin -d etl_portfolio_dev \
    -c "SELECT COUNT(*), SUM(montant) FROM ventes;"
```

---

## 🚀 ÉTAPE 7 — Voir les outputs

```bash
terraform output

# Résultat :
# conteneur_etl      = "etl-dev-etl"
# conteneur_postgres = "etl-dev-postgres"
# db_connexion       = "postgresql://admin@localhost:5432/etl_portfolio_dev"
# db_password        = <sensitive>
# reseau             = "etl-dev-net"
# volume_pgdata      = "etl-dev-pgdata"

# Voir le mot de passe généré (sensitive)
terraform output -raw db_password

# Config JSON générée
cat output/docker_config.json
```

---

## 🚀 ÉTAPE 8 — Vérifier les fichiers CSV de sortie

```bash
# Le conteneur ETL écrit dans /output → monté sur ./output/
ls output/
# ventes_2024-01-01.csv

cat output/ventes_2024-01-01.csv | head
```

---

## 🚀 ÉTAPE 9 — Modifier et réappliquer

```bash
# Changer le nombre de replicas ou le port
# Modifier variables.tf ou terraform.tfvars

# Terraform détecte les changements
terraform plan

# Appliquer → recrée seulement ce qui a changé
terraform apply -auto-approve
```

---

## 🚀 ÉTAPE 10 — Détruire la stack

```bash
# Détruire tous les conteneurs, réseaux, volumes
terraform destroy -auto-approve

# Les images Docker restent (keep_locally = true)
docker images | grep -E "postgres|python"

# Vérifier que les conteneurs sont bien supprimés
docker ps -a | grep etl
```

---

## 💡 Terraform vs docker-compose

| | docker-compose | Terraform + Docker |
|---|---|---|
| **Syntaxe** | YAML | HCL |
| **State** | Aucun | terraform.tfstate |
| **Plan** | Non | ✓ terraform plan |
| **CI/CD** | Possible | Natif |
| **Multi-cloud** | Non | ✓ (même outil) |
| **Complexité** | Faible | Moyenne |

---



---

⭐ **Si ce projet t'aide, mets une étoile !**
