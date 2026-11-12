terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

data "aws_region" "current" {}

provider "aws" {
  default_tags {
    tags = local.provider_default_tags
  }
}

# NOTE: the exec plugin's `aws-eks-get-token-retry` is a runtime contract with
# whatever executes addon roots (deploy image OR CI checklist) — on GitHub
# runners, the consuming org fork's workflows put ./bin on PATH (see bin/).

provider "kubectl" {
  load_config_file = false

  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    # Wraps `aws eks get-token` with short retries — concurrent exec-plugin
    # invocations race on the AWS CLI's local credential cache (see bin/).
    command = "aws-eks-get-token-retry"
    args = [
      "eks", "get-token",
      "--cluster-name", data.aws_eks_cluster.cluster.id,
      "--region", data.aws_region.current.region,
      "--role-arn", var.eks_cluster_role_arn,
    ]
  }
}
