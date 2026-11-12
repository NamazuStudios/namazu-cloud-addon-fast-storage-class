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

## Bootstrap: none — by design

This addon creates **no AWS resources** and needs **no IAM feature grants**
beyond the executor base: everything it makes is Kubernetes objects
(StorageClass + ValidatingAdmissionPolicy + Binding). There is no bootstrap
script because there is nothing to bootstrap — the consuming org fork's
bootstrap (executor identity, `iam.policy.json`, RBAC) is the only setup,
and the only RBAC this addon adds to that is the `storage.k8s.io` +
`admissionregistration.k8s.io` rules documented above. Account-wide
surfaces: none.

## License & provenance

**AGPL-3.0** — see [LICENSE](LICENSE).

Part of the [Namazu Cloud Addon system](https://github.com/NamazuStudios/namazu-cloud-addon).

This is an **official Namazu Cloud addon** — it can be activated for a
**fixed fee** (the activation + review process is documented in the
[namazu-cloud-addon-example template's ADDONS.md](https://github.com/NamazuStudios/namazu-cloud-addon/blob/main/ADDONS.md)).

The repository is made public for **transparency and visibility**: it is
deeply connected to Namazu Cloud — the tenant-named StorageClass scheme,
the provisioned-performance knobs, and the namespace guard here are the
platform's storage story. It is written for Namazu Studios and Namazu
Cloud use; derivative works are expected to come back upstream to
`NamazuStudios`, no exceptions.

## AGPL waiver for delivered work

Namazu Studios, as the copyright holder, **waives all AGPL obligations for
software installed through a purchase or other business arrangement
between Namazu Studios and the client.** The AGPL terms above govern the
code as published in this repository; work delivered to you under
contract — including any official addon activated for a fee or custom
addon authored for you — is delivered under that agreement, not under the
license's reciprocity terms.

## Built for generative AI cold starts

The measured case this addon exists for: a **generative AI worker pod**
starts, clones its weights volume **from an EBS snapshot**, and the model
loader page-faults through the lazily-restored volume — a multi-GB
checkpoint (diffusion DiT, LLM, or the LoRA adapters stacked on it)
crawling at ~14 MB/s for a quarter hour before the first inference.

- **Provisioned throughput is the fix**: gp3 at 16,000 IOPS + 1,000
  MiB/s turns that crawl into a couple of minutes; with the tenant-side
  parallel pre-read, ready-to-generate drops from ~25 min to ~8-10 min.
- **Per-tenant classes, per-tenant billing** — the class is named for the
  namespace and labels carry the tenant ids, so GenAI spend attributes
  cleanly.
- **One tenant cannot borrow another's class** — the ValidatingAdmission
  guard denies PVCs referencing the class outside its namespace.
- **Layer with LoRA serving** — adapters stacked on a base checkpoint
  restore through the same volume; the fast class makes swapping adapters
  per request practical.
