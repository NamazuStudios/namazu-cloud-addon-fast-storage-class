# namazu-cloud-addon-fast-storage-class

Per-tenant **fast StorageClass** as a shared addon: one EBS CSI class per
install, named for the tenant it serves, with provisioned IOPS/throughput and
a hard namespace guard.

One repo = one addon = one Terraform root (contract:
[`tenant-addons-plan.md`](https://github.com/NamazuStudios/namazu-cloud-instance/blob/main/tenant-addons-plan.md)).
Inert by design: no CI, no bootstrap, no AWS role — an org fork executes
this root under **its** executor role at a pinned ref. There is no
statically-bound config: **the consuming fork's matrix entry IS the request
and the config** (the runner's `contract` input), and the inputs are
deliberately default-less — no contract values, no valid plan.

## What it creates (per install)

- **StorageClass** `<namespace-id>-<storage-class-name>` (namespace-id = the
  tenant id: instance or workspace), with the tenant's audit labels
  (`organization_id` + `instance_id`/`workspace_id`) for billing attribution.
  Parameters: `type`, `iops`, `throughput` (gp3 only, when > 0), `encrypted`.
  `WaitForFirstConsumer`, expandable.
- **ValidatingAdmissionPolicy + Binding** (`<class>-namespace-guard`):
  denies any PVC referencing this class from a namespace other than the
  owning tenant's — enforced, not convention (decision 2026-11-12). Needs
  the `admissionregistration.k8s.io` RBAC rule once in consuming forks'
  `rbac.tf`.

## Inputs (per entry, via the runner's `contract`)

| Input | Type | Notes |
|---|---|---|
| `storage_class_name` | string | the tail of the class name; default-less |
| `storage_class_type` | string | `gp3`, `io2`, ...; default-less |
| `provisioned_iops` | number | default-less |
| `throughput_mbps` | number | optional (gp3 max 1000); 0 = omit |

## Multiple instances per tenant (variant)

Every install is the triple (addon, variant, tenant) — several variants on
one tenant are independent applies. Example (Dank Studios, one workspace):

```yaml
- { addon: ".../namazu-cloud-addon-fast-storage-class", ref: "<pin>", variant: g5,
    workspace: "<id>",
    contract: |-
      storage_class_name=fast
      storage_class_type=gp3
      provisioned_iops=16000
      throughput_mbps=1000 }
- { addon: ".../namazu-cloud-addon-fast-storage-class", ref: "<pin>", variant: archive,
    workspace: "<id>",
    contract: |-
      storage_class_name=archive
      storage_class_type=io2
      provisioned_iops=32000 }
```

## Outputs

`$addon.fast-storage-class.<variant>.storage_class_name` — tenant charts
point their `storageClassName` at it.

## Reference

Fake The Music measured the cold-start problem this solves
(namazu-cloud-addon-dank-studios#1): DiT weights crawl at ~14 MB/s through
lazily-restored EBS (~16 min/pod); provisioned gp3 (16,000 IOPS +
1,000 MiB/s) plus the tenant-side volume pre-read takes ready-to-claim from
~25 min to ~8-10 min.

## License

MIT — see [LICENSE](LICENSE).
