# terraform-demo-app

Terraform + Azure Functions implementation for near real-time Microsoft Teams transcript ingestion, AI analysis, and append-only storage in Azure Blob Storage.

## What this provisions

- Azure AD App Registration + Service Principal with Graph application permissions:
  - `Calls.Read.All`
  - `OnlineMeetings.Read.All`
  - `OnlineMeetingTranscript.Read.All`
- Graph permission assignments (admin consent still required in tenant)
- Resource Group
- Storage Account
  - Queue (`transcript-ingestion`) for decoupled transcript processing
  - Blob container (`analysis-docs`) for append-only analysis document
- Service Bus Namespace + Queue (for future extension)
- Key Vault for sensitive values (Graph client secret, OpenAI key, Service Bus connection string)
- Linux Consumption Function App (Python 3.11)
- Log Analytics + Application Insights
- Optional Azure OpenAI account (`create_openai_resource=true`)

## Function app workflow

The `function-app` folder contains three Azure Functions (Python v2 programming model):

1. `GraphNotifications` (HTTP trigger)
   - Handles Graph `validationToken` handshake
   - Validates `clientState`
   - Fetches transcript metadata/content from Graph
   - Enqueues raw transcript payload to Azure Storage Queue

2. `AnalyzeTranscript` (Queue trigger)
   - Pulls transcript payload from queue
   - Calls Azure OpenAI for structured analysis
   - Appends markdown section to an append blob in `analysis-docs`

3. `RenewGraphSubscription` (Timer trigger, every 12h)
   - Renews configured Graph subscription if `GRAPH_SUBSCRIPTION_ID` exists
   - Creates a new subscription otherwise

## Deploy Terraform

```bash
cd /home/runner/work/terraform-demo-app/terraform-demo-app
terraform init
terraform plan \
  -var="webhook_base_url=https://<your-function-host>" \
  -var="graph_subscription_client_state=<random-shared-secret>" \
  -var="azure_openai_existing_endpoint=https://<your-openai>.openai.azure.com" \
  -var="azure_openai_api_key=<openai-key>"
terraform apply \
  -var="webhook_base_url=https://<your-function-host>" \
  -var="graph_subscription_client_state=<random-shared-secret>" \
  -var="azure_openai_existing_endpoint=https://<your-openai>.openai.azure.com" \
  -var="azure_openai_api_key=<openai-key>"
```

If you have Azure OpenAI quota and want Terraform to provision it:

```bash
terraform apply \
  -var="webhook_base_url=https://<your-function-host>" \
  -var="graph_subscription_client_state=<random-shared-secret>" \
  -var="create_openai_resource=true"
```

## Deploy function code

Deploy `function-app` to the provisioned Function App with your preferred CI/CD or Azure Functions Core Tools.

For local development:

```bash
cp /home/runner/work/terraform-demo-app/terraform-demo-app/function-app/local.settings.sample.json \
   /home/runner/work/terraform-demo-app/terraform-demo-app/function-app/local.settings.json
```

Then fill required settings and run Functions Core Tools from `function-app`.

## Notes

- Graph subscriptions for this resource expire quickly; timer renewal is required.
- Graph transcript availability is near real-time (usually minutes after meeting completion), not live.
- Append blob usage avoids read/modify/write contention when many transcripts arrive concurrently.
