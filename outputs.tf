output "reseau" {
  value = docker_network.etl_network.name
}
output "conteneur_postgres" {
  value = docker_container.postgres.name
}
output "conteneur_etl" {
  value = docker_container.etl.name
}
output "volume_pgdata" {
  value = docker_volume.pgdata.name
}
output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}
output "db_connexion" {
  value = "postgresql://admin@localhost:${var.db_port_externe}/${var.nom_projet}_${var.environnement}"
}
