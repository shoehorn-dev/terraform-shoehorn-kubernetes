output "url" {
  description = "Shoehorn portal URL"
  value       = "${var.health_check_protocol}://${var.domain}"
}

output "namespace" {
  description = "Kubernetes namespace where Shoehorn is deployed"
  value       = kubernetes_namespace_v1.shoehorn.metadata[0].name
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.shoehorn.name
}

output "release_status" {
  description = "Helm release status"
  value       = helm_release.shoehorn.status
}

output "chart_version" {
  description = "Deployed Helm chart version"
  value       = helm_release.shoehorn.version
}

output "agent_deployed" {
  description = "Whether the K8s agent was deployed"
  value       = var.deploy_agent
}

output "agent_token_prefix" {
  description = "K8s agent token prefix (for identification)"
  value       = var.deploy_agent ? shoehorn_k8s_agent.cluster[0].token_prefix : null
}

output "agent_status" {
  description = "K8s agent registration status"
  value       = var.deploy_agent ? shoehorn_k8s_agent.cluster[0].status : null
}
