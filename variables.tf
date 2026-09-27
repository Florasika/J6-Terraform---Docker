variable "nom_projet" {
  type    = string
  default = "etl_portfolio"
}
variable "environnement" {
  type    = string
  default = "dev"
}
variable "db_port_externe" {
  description = "Port PostgreSQL exposé sur l'hôte"
  type        = number
  default     = 5432
}

variable "app_host_path" {
  description = "Chemin absolu hote vers le dossier app/ (bind mount conteneur ETL)"
  type        = string
}

variable "output_host_path" {
  description = "Chemin absolu hote vers le dossier output/ (bind mount conteneur ETL)"
  type        = string
}
