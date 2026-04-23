# terraform-demo-app

Terraform infrastructure for the `demo-app` application.

Managed by [snow-tf-platform](https://github.com/natesanshreyas/terraform-modules) — Terraform is generated automatically from ServiceNow tickets by AI agents.

## Structure

```
{environment}/{ticket_id}/{unit_id}/
  main.tf        # Generated module call
  variables.tf   # Variable declarations
```
