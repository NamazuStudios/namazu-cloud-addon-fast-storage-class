# What other addons (and operators) can wire against. Resolves per install:
# $addon.fast-storage-class.<variant>.<output>

output "storage_class_name" {
  description = "The full StorageClass name (<namespace-id>-<storage-class-name>) — tenant charts point their storageClassName here."
  value       = local.storage_class_name
}

output "provisioned" {
  description = "The provisioned performance as applied (audit-friendly: compare against the entry's contract values)."
  value = {
    type       = var.storage_class_type
    iops       = var.provisioned_iops
    throughput = var.throughput_mbps
  }
}
