# Addon-owned inputs — fed per install from the consuming fork's matrix entry
# via the runner's `contract` input (--contract KEY=JSON). They are
# DELIBERATELY default-less: no contract values, no valid plan (the entry is
# the request AND the config). Contract variables (instance_id,
# organization_id, ...) are NOT declared here: see 20-variables.tf and
# author rule 1 in feature.tf.

variable "storage_class_name" {
  description = "The tail of the class name: the full name is <namespace-id>-<storage-class-name> (namespace-id = the tenant id the entry targets). Reference it later by this name."
  type        = string
}

variable "storage_class_type" {
  description = "EBS type: gp3, io2, ... (passed to the EBS CSI driver's `type` parameter)."
  type        = string
}

variable "provisioned_iops" {
  description = "Provisioned IOPS for the class's volumes."
  type        = number
}

variable "throughput_mbps" {
  description = "Provisioned throughput in MiB/s (gp3 only, max 1000 — dank#1's measured fix needs 1000). 0 = omit the parameter (io2/io1 don't take it)."
  type        = number
  default     = 0
}
