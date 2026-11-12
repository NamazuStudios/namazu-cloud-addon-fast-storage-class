# Per-tenant fast StorageClass — one class per install, named for its tenant:
#
#   <namespace-id>-<storage-class-name>
#
# namespace-id is the tenant identity (instance_id or workspace_id — the
# addon contract's 10-locals.tf computes it as addon_namespace), so classes
# never collide across tenants and the owning tenant is legible in every
# chart reference.
#
# Namespace-only access is ENFORCED (design decision 2026-11-12, not
# convention): a ValidatingAdmissionPolicy + Binding denies PVCs referencing
# this class from any namespace except the owning tenant's. The VAP+Binding
# are addon-created and swept with the entry; consuming forks add the
# admissionregistration.k8s.io RBAC rule once in rbac.tf.
#
# Billing attribution: the class carries the tenant's audit labels
# (organization_id + instance_id/workspace_id — common_labels), and volumes
# provisioned through the class inherit the EBS CSI driver's tag propagation
# so AWS cost allocation follows the tenant.
#
# The two author rules (contract, stated inline so consumers inherit them):
#  1. NEVER re-declare a variable from 20-variables.tf — those are the
#     tenant contract, not yours. Addon-semantics inputs live in variables.tf
#     and are fed from the fork's matrix contract values.
#  2. NEVER couple to another addon except through its outputs (via
#     `$addon.<id>.<variant>.<output>` bindings in manifest.yaml).

locals {
  storage_class_name = "${local.addon_namespace}-${var.storage_class_name}"
}

resource "kubectl_manifest" "storage_class" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name   = local.storage_class_name
      labels = local.common_labels
    }
    provisioner = "ebs.csi.aws.com"
    parameters = merge(
      {
        type      = var.storage_class_type
        iops      = tostring(var.provisioned_iops)
        encrypted = "true"
      },
      var.throughput_mbps > 0 ? { throughput = tostring(var.throughput_mbps) } : {},
    )
    volumeBindingMode    = "WaitForFirstConsumer"
    allowVolumeExpansion = true
    reclaimPolicy        = "Delete"
  })
}

# The namespace guard: any PVC anywhere referencing this class is denied
# unless it lives in the owning tenant's namespace (namespaceObject CEL var).
resource "kubectl_manifest" "namespace_guard_policy" {
  yaml_body = yamlencode({
    apiVersion = "admissionregistration.k8s.io/v1"
    kind       = "ValidatingAdmissionPolicy"
    metadata = {
      name   = "${local.storage_class_name}-namespace-guard"
      labels = local.common_labels
    }
    spec = {
      failurePolicy = "Fail"
      matchConstraints = {
        resourceRules = [{
          apiGroups   = [""]
          apiVersions = ["v1"]
          operations  = ["CREATE", "UPDATE"]
          resources   = ["persistentvolumeclaims"]
        }]
      }
      validations = [{
        expression = "object.spec.storageClassName != '${local.storage_class_name}' || namespaceObject.metadata.name == '${local.addon_namespace}'"
        message    = "storage class '${local.storage_class_name}' is reserved for tenant '${local.addon_namespace}' (owned by the fast-storage-class addon install)"
        reason     = "Forbidden"
      }]
    }
  })
}

resource "kubectl_manifest" "namespace_guard_binding" {
  yaml_body = yamlencode({
    apiVersion = "admissionregistration.k8s.io/v1"
    kind       = "ValidatingAdmissionPolicyBinding"
    metadata = {
      name   = "${local.storage_class_name}-namespace-guard"
      labels = local.common_labels
    }
    spec = {
      policyName        = "${local.storage_class_name}-namespace-guard"
      validationActions = ["Deny"]
    }
  })
}
