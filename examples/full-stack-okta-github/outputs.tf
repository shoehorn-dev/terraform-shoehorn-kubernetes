output "url" {
  description = "Public URL of the deployed Shoehorn instance"
  value       = module.shoehorn.url
}

output "namespace" {
  description = "Kubernetes namespace where Shoehorn is deployed"
  value       = module.shoehorn.namespace
}

output "agent_deployed" {
  description = "Whether the K8s agent was deployed in this apply"
  value       = module.shoehorn.agent_deployed
}

output "agent_status" {
  description = "Current status of the K8s agent registration"
  value       = module.shoehorn.agent_status
}
