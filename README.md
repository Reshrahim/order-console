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

- A Kubernetes cluster to host Radius control plane and the application. 
- [Radius installed on your Kubernetes cluster](https://docs.radapp.io/tutorials/install-radius/) Note: Your user must have the Kubernetes cluster-admin role to install Radius and deploy the sample application.
- [Dapr installed on your Kubernetes cluster](https://docs.dapr.io/operations/hosting/kubernetes/kubernetes-deploy/)
- [Azure cloud provider configured in Radius](https://docs.radapp.io/guides/operations/providers/azure-provider/) (for Azure deployment only)

### 1. Create Dapr resource types

```bash
rad resource-type create -f radius/types.yaml
```

### 2. Bicep extension

The Bicep extension is already available in the `radius/extensions` folder as `radiusdapr.tgz`. If you make changes to the `types.yaml`, run the following command to create a new archive and update the extension in Radius:

```bash
rad bicep publish-extension -f radius/types.yaml --target radius/extensions/radiusdapr.tgz
```

### 3. Verify the extension in `bicepconfig.json`

Open `radius/bicepconfig.json` and verify the `radiusdapr` extension references the correct archive file:

```jsonc
{
  "extensions": {
    "radius": "br:biceptypes.azurecr.io/radius:edge",
    "radiusdapr": "extensions/radiusdapr.tgz"
  }
}
```

### 4. Use Published Recipes

Recipes are Terraform configurations stored in a Git repository. When you register a recipe with Radius, you create a pointer to the Terraform configuration. In this sample we use published Recipes via Git references and no additional authentication is needed. Check out the Recipe guide to learn how to create and publish your own Recipes: https://docs.radapp.io/guides/recipes/howto-author-recipes/

**Kubernetes Recipes**
- `recipes/stateStores/kubernetes/main.tf` — PostgreSQL 16 deployed in-cluster with a Dapr `state.postgresql` component
- `recipes/pubSubBrokers/kubernetes/main.tf` — Apache Kafka (KRaft mode) deployed in-cluster with a Dapr `pubsub.kafka` component

**Azure Recipes**
- `recipes/stateStores/azure/main.tf` — Azure Database for PostgreSQL Flexible Server with a Dapr `state.postgresql` component
- `recipes/pubSubBrokers/azure/main.tf` — Azure Event Hubs (Kafka-enabled) with a Dapr `pubsub.kafka` component

### 5a. Set up a Kubernetes Environment

If you want to deploy the sample application to your Kubernetes cluster with in-cluster Dapr components, follow the steps below to set up the Kubernetes environment and register the Kubernetes Recipes. If you have configured the Azure provider and want to deploy to Azure, skip to the next section.

Create a resource group and deploy the Kubernetes environment:

```bash
rad group create local
```

```bash
rad deploy radius/environments/kubernetes.bicep --group local
```

>[!NOTE] If you hit an error "No environment name or ID provided, pass in an environment name or ID" create an environment first with `rad environment create azure --group azure` and then run the deploy command again. This is a temporary workaround and should be fixed in v0.55.0 release.

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

>[!NOTE] Follow the instructions in the [Azure provider guide](https://docs.radapp.io/guides/operations/providers/azure-provider/) to set up your Azure environment and register your Azure credentials with Radius before proceeding with the steps below.

Create a resource group and deploy the Azure environment:

```bash
rad group create azure
```

Deploy the Azure environment, passing your Azure subscription and resource group:

```bash
rad deploy radius/environments/azure.bicep --group azure \
  -p azureSubscriptionId=<subscription-id> \
  -p azureResourceGroup=<resource-group> \
  -p location=<location>
```
>[!NOTE] If you hit an error "No environment name or ID provided, pass in an environment name or ID" create an environment first with `rad environment create azure --group azure` and then run the deploy command again. This is a temporary workaround and should be fixed in v0.55.0 release.

This creates a `azure` environment with Azure-backed recipes and configures the Azure provider scope.

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

Switch to the environment you want to deploy to:

```bash
rad environment switch <environment-name>
```

```bash
rad deploy radius/app.bicep
```

If you hit an error like below on service account permissions when deploying the application, it means the service account `dynamic-rp` in the `radius-system` namespace does not have the necessary permissions to list CRDs and interact with Dapr components.

```
terraform apply failure: exit status 1\n\nError: Plugin error\n\nThe plugin returned an unexpected error from\nplugin6.(*GRPCProvider).PlanResourceChange: rpc error: code = Unknown desc =\nfailed to determine resource type ID: failed to look up GVK\n[dapr.io/v1alpha1, Kind=Component] among available CRDs:\ncustomresourcedefinitions.apiextensions.k8s.io is forbidden: User\n\"system:serviceaccount:radius-system:dynamic-rp\" cannot list resource\n\"customresourcedefinitions\" in API group \"apiextensions.k8s.io\" at the\ncluster scope\n" make sure the service account `dynamic-rp` in the `radius-system` namespace has the necessary permissions to list CRDs and interacrt with dapr components.
```

You can grant the permissions by creating a ClusterRoles and bind them to the service account with the following commands:

      ```bash
      # dapr.io permissions
      kubectl create clusterrole radius-dapr-manager \
        --verb=create,delete,get,list,patch,update,watch \
        --resource=components.dapr.io,subscriptions.dapr.io,configurations.dapr.io,resiliencies.dapr.io

      kubectl create clusterrolebinding radius-dapr-manager-binding \
        --clusterrole=radius-dapr-manager \
        --serviceaccount=radius-system:dynamic-rp

      # apiextensions.k8s.io permissions
      kubectl create clusterrole radius-crd-reader \
        --verb=get,list,watch \
        --resource=customresourcedefinitions.apiextensions.k8s.io

      kubectl create clusterrolebinding radius-crd-reader-binding \
        --clusterrole=radius-crd-reader \
        --serviceaccount=radius-system:dynamic-rp
      ```

Deployment may take 15-20 minutes for Azure resources.

```bash
Deployment In Progress...

Completed            order-console   Applications.Core/applications
Completed            statestore      Radius.Dapr/stateStores
Completed            pubsub          Radius.Dapr/pubSubBrokers
Completed            frontend-ui     Applications.Core/containers
.                    fulfillment-worker Applications.Core/containers
.                    orders-api      Applications.Core/containers

Deployment Complete

Resources:
    order-console   Applications.Core/applications
    frontend-ui     Applications.Core/containers
    fulfillment-worker Applications.Core/containers
    orders-api      Applications.Core/containers
    pubsub          Radius.Dapr/pubSubBrokers
    statestore      Radius.Dapr/stateStores
```

Access the application by port-forwarding:

```bash
kubectl port-forward svc/frontend-ui 3000:3000 -n <namespace>
```

Open **http://localhost:3000** in your browser.

### 7. Clean up

Delete the application:

```bash
rad app delete -a order-console
```
