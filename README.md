# Order Management Application with Dapr and Radius

This sample demonstrates a microservices order-processing application that uses [Dapr](https://dapr.io) for state management and pub/sub messaging, leveraging [Radius](https://radapp.io) for deployment across Kubernetes and Azure.

## Sample Overview

```
┌──────────────┐  POST /api/orders  ┌─────────────┐  Dapr publish  ┌───────┐
│   Next.js UI │ ─────────────────► │ orders-api  │ ─────────────► │ Kafka │
│              │  SSE /events/stream│ (port 3000) │  topic:orders  └───┬───┘
└──────────────┘ ◄───────────────── └──────┬──────┘                    │
                                           │ Dapr state                │ Dapr subscription
                                           ▼                           ▼
                                    ┌────────────┐            ┌────────────────────┐
                                    │ PostgreSQL │ ◄───────── │ fulfillment-worker │
                                    │(statestore)│  Dapr state│    (port 3002)     │
                                    └────────────┘            └────────────────────┘
```

This sample showcases how to deploy a containerized microservices application that connects to different infrastructure backends using Radius. The sample includes:

- Resource type definitions for Dapr components in `types.yaml`
- Terraform recipes for deploying infrastructure to Kubernetes and Azure
- `app.bicep` that defines the three services and connections to infrastructure

### Application UI

![alt text](image.png)

## How to deploy the sample?

### Pre-requisites

- A Kubernetes cluster to host Radius control plane and the application
- [Radius CLI](https://docs.radapp.io/tutorials/install-radius/)
- [Radius installed on your Kubernetes cluster](https://docs.radapp.io/guides/operations/kubernetes/install/)
- [Dapr installed on your Kubernetes cluster](https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-deploy/)
- [Azure cloud provider configured in Radius](https://docs.radapp.io/guides/operations/providers/overview/) (for Azure deployment only)

### 1. Create Dapr resource types

```bash
rad resource-type create stateStores -f radius/types/types.yaml
rad resource-type create pubSubBrokers -f radius/types/types.yaml
```

### 2. Create Bicep extension

```bash
rad bicep publish-extension -f radius/types/types.yaml --target radius/extensions/radiusdapr.tgz
```

### 3. Verify the extension in `bicepconfig.json`

Open `radius/bicepconfig.json` and verify the `radiusdapr` extension references the correct archive file:

```jsonc
{
  "experimentalFeaturesEnabled": {
    "extensibility": true
  },
  "extensions": {
    "radius": "br:biceptypes.azurecr.io/radius:edge",
    "radiusdapr": "extensions/radiusdapr.tgz"
  }
}
```

### 4. Publish Recipes

Recipes are Terraform configurations stored in a Git repository. When you register a recipe with Radius, you create a pointer to the Terraform configuration. In this sample we use public Git references and no additional authentication is needed. If you need private registry authentication see [this guide](https://docs.radapp.io/guides/recipes/terraform/howto-private-registry/).

**Kubernetes Recipes**
- `recipes/stateStores/kubernetes/main.tf` — PostgreSQL 16 deployed in-cluster with a Dapr `state.postgresql` component
- `recipes/pubSubBrokers/kubernetes/main.tf` — Apache Kafka (KRaft mode) deployed in-cluster with a Dapr `pubsub.kafka` component

**Azure Recipes**
- `recipes/stateStores/azure/main.tf` — Azure Database for PostgreSQL Flexible Server with a Dapr `state.postgresql` component
- `recipes/pubSubBrokers/azure/main.tf` — Azure Event Hubs (Kafka-enabled) with a Dapr `pubsub.kafka` component

### 5a. Set up a Kubernetes Environment

Create a resource group and deploy the Kubernetes environment:

```bash
rad group create local
```

```bash
rad deploy radius/environments/kubernetes.bicep --group local
```

This creates a `local` environment and registers the Kubernetes recipes.

Create a workspace:

```bash
rad workspace create kubernetes local \
  --context $(kubectl config current-context) \
  --environment local \
  --group local
```

Confirm the environment was created:

```
$ rad environment list
RESOURCE   TYPE                            GROUP    STATE
local      Applications.Core/environments  local    Succeeded
```

Confirm the Recipes were registered:

```
$ rad recipe list
RECIPE    TYPE                          TEMPLATE KIND  TEMPLATE
default   Radius.Dapr/stateStores       terraform      git::https://github.com/Reshrahim/order-console.git//radius/recipes/stateStores/kubernetes
default   Radius.Dapr/pubSubBrokers     terraform      git::https://github.com/Reshrahim/order-console.git//radius/recipes/pubSubBrokers/kubernetes
```

### 5b. Set up an Azure Environment

Create a resource group and deploy the Azure environment:

```bash
rad group create azure
```

Configure the Azure credential provider:

```bash
rad credential register azure sp \
  --client-id <app-id> \
  --client-secret <password> \
  --tenant-id <tenant-id>
```

Deploy the Azure environment, passing your Azure subscription and resource group:

```bash
rad deploy radius/environments/azure.bicep --group azure \
  -p azureSubscriptionId=<subscription-id> \
  -p azureResourceGroup=<resource-group>
```

This creates a `azure` environment with Azure-backed recipes and configures the Azure provider scope.

Register the Azure credentials with Radius to authenticate to Azure and provision resources:

```bash
rad credential register azure sp \
  --client-id <app-id> \
  --client-secret <password> \
  --tenant-id <tenant-id>
```

Create a workspace:

```bash
rad workspace create kubernetes azure \
  --context $(kubectl config current-context) \
  --environment azure \
  --group azure
```

Confirm the environment was created:

```
$ rad environment list
RESOURCE   TYPE                            GROUP    STATE
azure      Applications.Core/environments  azure    Succeeded
```

Confirm the Recipes were registered:

```
$ rad recipe list
RECIPE    TYPE                          TEMPLATE KIND  TEMPLATE
default   Radius.Dapr/stateStores       terraform      git::https://github.com/Reshrahim/order-console.git//radius/recipes/stateStores/azure
default   Radius.Dapr/pubSubBrokers     terraform      git::https://github.com/Reshrahim/order-console.git//radius/recipes/pubSubBrokers/azure
```

### 6. Deploy the Order Management Application

```bash
rad deploy radius/app.bicep
```

Access the application by port-forwarding:

```bash
kubectl port-forward svc/frontend-ui 3000:3000 -n azure-order-console
```

Open **http://localhost:3000** in your browser.

### 7. Clean up

Delete the application:

```bash
rad app delete -a order-console
```

## Infrastructure & Recipes

### Kubernetes

In-cluster infrastructure — no cloud account needed:

| Resource | Backing Service | Recipe |
|----------|----------------|--------|
| `statestore` | PostgreSQL 16 (StatefulSet) | `recipes/stateStores/kubernetes/main.tf` |
| `pubsub` | Apache Kafka (KRaft mode) | `recipes/pubSubBrokers/kubernetes/main.tf` |

### Azure

Managed Azure services for production workloads:

| Resource | Backing Service | Recipe |
|----------|----------------|--------|
| `statestore` | Azure Database for PostgreSQL Flexible Server | `recipes/stateStores/azure/main.tf` |
| `pubsub` | Azure Event Hubs (Kafka-enabled namespace) | `recipes/pubSubBrokers/azure/main.tf` |
