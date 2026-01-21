variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Cluster name"
  type        = string
  default     = "dev-eks-karpenter-demo"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Terraform = "true"
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"
}

variable "karpenter_version" {
  description = "Karpenter version to install"
  type        = string
  default     = "1.8.4"
}

variable "karpenter_replicas" {
  description = "Number of Karpenter controller replicas"
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway for cost savings "
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway for cost savings "
  type        = bool
  default     = false
}

variable "endpoint_public_access" {
  description = "Enable public access to EKS API server"
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the EKS API server publicly"
  type        = list(string)
  default     = []
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable admin permissions for cluster creator "
  type        = bool
  default     = false
}

variable "node_pool_cpu_limit" {
  description = "CPU limit for Karpenter node pools"
  type        = string
  default     = "200"
}

variable "node_pool_consolidation_budget_nodes" {
  description = "Consolidation budget for node pools (percentage or number)"
  type        = string
  default     = "10%"
}

variable "enable_karpenter_manifests" {
  type    = bool
  default = false
}