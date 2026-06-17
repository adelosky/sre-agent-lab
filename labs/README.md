# Labs

Each folder in this directory contains a separate Azure SRE Agent scenario. Run deployment commands from inside the lab folder unless the lab README says otherwise.

| Lab | Scenario | Start here |
| --- | --- | --- |
| [starter-lab](starter-lab/README.md) | Grubify on Container Apps with Azure Monitor incidents, knowledge files, GitHub issue triage, and response plans. | `cd labs/starter-lab` |
| [deployment-compliance](deployment-compliance/README.md) | Deployment compliance checks for a Container App workload. | `cd labs/deployment-compliance` |
| [terraform-drift-detection](terraform-drift-detection/README.md) | Terraform drift detection through Terraform Cloud or simulated webhook events. | `cd labs/terraform-drift-detection/terraform` |
| [vm-cosmosdb](vm-cosmosdb) | VM and Azure Cosmos DB diagnostics with scheduled compliance drift checks. | `cd labs/vm-cosmosdb` |
| [zava-aks-postgres](zava-aks-postgres/README.md) | AKS and PostgreSQL incident remediation demo. | `cd labs/zava-aks-postgres` |

For `azd` labs, create a unique environment per lab before deploying:

```bash
azd env new <unique-env-name>
azd up
```

The Terraform drift lab does not use `azd`; follow its README and run Terraform from its `terraform/` directory.