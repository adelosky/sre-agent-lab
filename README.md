# Azure SRE Agent Labs

This repository collects the Azure SRE Agent lab scenarios under one workspace so each lab can be deployed independently for demos.

## Lab Catalog

| Lab | Scenario | Deployment entry point |
| --- | --- | --- |
| [starter-lab](labs/starter-lab/README.md) | Container Apps sample with Grubify, Azure Monitor incidents, knowledge files, GitHub issue triage, and SRE Agent response plans. | `cd labs/starter-lab` then `azd up` |
| [deployment-compliance](labs/deployment-compliance/README.md) | Container App deployment compliance checks, approval hooks, scheduled scans, and remediation workflows. | `cd labs/deployment-compliance` then `azd up` |
| [terraform-drift-detection](labs/terraform-drift-detection/README.md) | Terraform drift investigation triggered by Terraform Cloud or a simulated webhook. | `cd labs/terraform-drift-detection/terraform` then `terraform apply` |
| [vm-cosmosdb](labs/vm-cosmosdb) | VM and Azure Cosmos DB diagnostics with SRE Agent skills, scheduled compliance drift checks, and break/fix scripts. | `cd labs/vm-cosmosdb` then `azd up` |
| [zava-aks-postgres](labs/zava-aks-postgres/README.md) | AKS and PostgreSQL application demo with SRE Agent runbooks and incident remediation. | `cd labs/zava-aks-postgres` then `azd up` |

## Deploy One Lab

Each lab is intended to stay self-contained. From the repository root, choose a lab folder and run that lab's commands from inside the folder.

```bash
cd labs/starter-lab
azd env new sre-starter
azd up
```

Use a unique `azd` environment name per lab so demos do not share resource groups or deployment state. Suggested names:

| Lab | Suggested environment |
| --- | --- |
| `starter-lab` | `sre-starter` |
| `deployment-compliance` | `sre-compliance` |
| `vm-cosmosdb` | `sre-vm-cosmos` |
| `zava-aks-postgres` | `sre-zava` |

The Terraform drift lab is Terraform-first rather than `azd`-first. Follow its README and create a local `terraform.tfvars` from the provided example.

## Repository Layout

```text
labs/
  deployment-compliance/
  starter-lab/
  terraform-drift-detection/
  vm-cosmosdb/
  zava-aks-postgres/
```

The `starter-lab` Grubify app remains a Git submodule at `labs/starter-lab/src/grubify`.

## Sync From Upstream

This repo tracks the upstream lab source through the `upstream` remote:

```bash
git fetch upstream main
git merge upstream/main
```

After syncing, review changes under `labs/` and test only the lab you plan to demo. Keep lab-specific deployment state, such as `.azure/`, local to the lab folder that owns it.

## Cleanup

Run teardown from the lab folder that created the environment:

```bash
cd labs/starter-lab
azd down --purge
```

For Terraform-based labs, use the cleanup command documented by that lab.