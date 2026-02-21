extension radius

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'local'
  location: 'global'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: 'local'
    }
    recipes: {
      'Radius.Dapr/stateStores': {
        default: {
          templateKind: 'terraform'
          templatePath: 'git::https://github.com/Reshrahim/order-console.git//radius/recipes/stateStores/kubernetes'
        }
      }
      'Radius.Dapr/pubSubBrokers': {
        default: {
          templateKind: 'terraform'
          templatePath: 'git::https://github.com/Reshrahim/order-console.git//radius/recipes/pubSubBrokers/kubernetes'
        }
      }
    }
  }
}
