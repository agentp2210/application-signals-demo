output "postgres_endpoint" {
  value = module.db.db_instance_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}