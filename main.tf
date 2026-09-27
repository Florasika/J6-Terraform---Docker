# ============================================================
#  JOUR 6 / 10 — Terraform : Terraform & Docker
#  Provider Docker — créer des conteneurs via Terraform
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ── Provider Docker ──────────────────────────────────────────
# Se connecte au daemon Docker local
provider "docker" {
  host = "unix:///var/run/docker.sock"   # Linux/Mac
  # Windows : host = "npipe:////.//pipe//docker_engine"
}

provider "local"  {}
provider "random" {}

# ── Locals ───────────────────────────────────────────────────
locals {
  projet  = var.nom_projet
  env     = var.environnement
  network = "${local.projet}-${local.env}-net"
}

# ── RESOURCE : Réseau Docker ──────────────────────────────────
resource "docker_network" "etl_network" {
  name   = local.network
  driver = "bridge"

  labels {
    label = "projet"
    value = local.projet
  }
  labels {
    label = "env"
    value = local.env
  }
}

# ── RESOURCE : Image Docker (pull) ────────────────────────────
resource "docker_image" "postgres" {
  name         = "postgres:15-alpine"
  keep_locally = true   # ne pas supprimer l'image au terraform destroy
}

resource "docker_image" "python" {
  name         = "python:3.11-slim"
  keep_locally = true
}

# ── RANDOM : mot de passe généré ─────────────────────────────
resource "random_password" "db_password" {
  length  = 16
  special = false
}

# ── RESOURCE : Conteneur PostgreSQL ──────────────────────────
resource "docker_container" "postgres" {
  name  = "${local.projet}-${local.env}-postgres"
  image = docker_image.postgres.image_id

  # Variables d'environnement
  env = [
    "POSTGRES_DB=${local.projet}_${local.env}",
    "POSTGRES_USER=admin",
    "POSTGRES_PASSWORD=${random_password.db_password.result}",
  ]

  # Port mapping : hôte:conteneur
  ports {
    internal = 5432
    external = var.db_port_externe
  }

  # Volume pour la persistance
  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  # Réseau
  networks_advanced {
    name = docker_network.etl_network.name
  }

  # Healthcheck
  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U admin -d ${local.projet}_${local.env}"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "10s"
  }

  # Labels
  labels {
    label = "projet"
    value = local.projet
  }
  labels {
    label = "env"
    value = local.env
  }

  # Redémarrer si crash
  restart = "on-failure"

  # Dépendance explicite
  depends_on = [docker_network.etl_network]
}

# ── RESOURCE : Volume Docker ──────────────────────────────────
resource "docker_volume" "pgdata" {
  name = "${local.projet}-${local.env}-pgdata"

  labels {
    label = "projet"
    value = local.projet
  }
}

# ── RESOURCE : Conteneur ETL ──────────────────────────────────
resource "docker_container" "etl" {
  name  = "${local.projet}-${local.env}-etl"
  image = docker_image.python.image_id

  # Commande à exécuter dans le conteneur
  command = ["sh", "-c",
  "pip install -q pandas 'psycopg[binary]' sqlalchemy && python /app/pipeline.py"
]

  # Variables d'environnement — injectées par Terraform
  env = [
    "DB_HOST=${local.projet}-${local.env}-postgres",
    "DB_PORT=5432",
    "DB_NAME=${local.projet}_${local.env}",
    "DB_USER=admin",
    "DB_PASSWORD=${random_password.db_password.result}",
    "PROJET=${local.projet}",
    "ENV=${local.env}",
  ]

  # Monter le script pipeline depuis l'hôte
  volumes {
    host_path      = var.app_host_path
    container_path = "/app"
    read_only      = true
  }

  # Monter le dossier output
  volumes {
    host_path      = var.output_host_path
    container_path = "/output"
  }

  networks_advanced {
    name = docker_network.etl_network.name
  }

  labels {
    label = "projet"
    value = local.projet
  }

  restart = "on-failure"

  depends_on = [
    docker_container.postgres,
    docker_network.etl_network,
  ]

}

# ── RESOURCE : Fichier de config généré ──────────────────────
resource "local_file" "docker_config" {
  filename = "${path.module}/output/docker_config.json"
  content  = jsonencode({
    reseau      = docker_network.etl_network.name
    postgres    = {
      container = docker_container.postgres.name
      port      = var.db_port_externe
      db_name   = "${local.projet}_${local.env}"
    }
    etl = {
      container = docker_container.etl.name
    }
    volume = docker_volume.pgdata.name
    note   = "Mot de passe dans terraform.tfstate (sensitive)"
  })
}
