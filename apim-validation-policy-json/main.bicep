targetScope = 'resourceGroup'
param tenantName string
// test

// APIM
param serviceName string

// ServiceBus
param serviceBusEndpoint string
param serviceBusQueueName1 string

var apiName = 'schema-validation-sample'
var apiDisplayName = 'Schema Validation Sample'
var apiSchemaGuid = guid('${resourceGroup().id}-${apiName}-schema')
var operation_addPerson = 'addperson'

var schemaExampleUser1 = 'john.doe@${tenantName}.onmicrosoft.com'

var schemaPersonRequired = [
  'firstName'
  'lastName'
]
var schemaPerson = {
  firstName: {
    type: 'string'
  }
  lastName: {
    type: 'string'
  }
  age: {
    type: 'integer'
    minimum: 0
  }
  email: {
    type: 'string'
    format: 'email'
    pattern: '^\\S+@\\S+\\.\\S+$'
  }
}
var personExample = {
  firstName: 'John'
  lastName: 'Doe'
  age: 25
  email: schemaExampleUser1
}

var authorizationPolicy = '''
        <!-- Service Bus Authorization-->
        <authentication-managed-identity resource="https://servicebus.azure.net/" output-token-variable-name="msi-access-token" ignore-error="false" />
        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
        </set-header>
        <set-header name="Content-Type" exists-action="override">
            <value>application/atom+xml;type=entry;charset=utf-8</value>
        </set-header>
        <set-header name="BrokerProperties" exists-action="override">
            <value>{}</value>
        </set-header>
'''

var mockResponse = '<mock-response status-code="200" content-type="application/json" />'

var validatePersonPolicy = '''
        <validate-content unspecified-content-type-action="detect" max-size="102400" size-exceeded-action="prevent" errors-variable-name="validationErrors">
          <content type="application/json" validate-as="json" action="prevent" schema-id="Portfolio" />
        </validate-content>
'''

var policySchema = '''
  <!--ADD {0}-->
  <policies>
      <inbound>
        <base />
        <!-- Validation -->
        {1}
        <!-- Authorization -->
        {2}
        <!-- Mock response -->
        {3}
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
'''

var personPolicy = format(policySchema, 'PORTFOLIO', validatePersonPolicy, authorizationPolicy, '<!-- N/A -->')

resource apiManagement 'Microsoft.ApiManagement/service@2021-08-01' existing = {
  name: serviceName
}

resource apiManagement_schemaPerson 'Microsoft.ApiManagement/service/schemas@2021-08-01' = {
  name: 'Person'
  parent: apiManagement
  properties: {
    schemaType: 'json'
    description: 'Schema for a Person Object'
    document: any({
      type: 'array'
      items: {
        type: 'object'
        properties: schemaPerson
        required: schemaPersonRequired
      }
    })
  }
}

resource apiManagement_apiName 'Microsoft.ApiManagement/service/apis@2021-08-01' = {
  name: '${serviceName}/${apiName}'
  properties: {
    displayName: 'Person Schema Validation Example'
    subscriptionRequired: true
    path: 'person-schema-validation'
    protocols: [
      'https'
    ]
    isCurrent: true
    description: 'Personal data ingestion'
    subscriptionKeyParameterNames: {
      header: 'Subscription-Key-Header-Name'
      query: 'subscription-key-query-param-name'
    }
  }
}
resource apiManagement_apiName_apiSchemaGuid 'Microsoft.ApiManagement/service/apis/schemas@2021-08-01' = {
  parent: apiManagement_apiName
  name: apiSchemaGuid
  properties: {
    contentType: 'application/vnd.oai.openapi.components+json'
    document: any({
      components: {
        schemas: {
          Definition_Person: {
            type: 'object'
            properties: schemaPerson
            required: schemaPersonRequired
            example: personExample
          }
        }
      }
    })
  }
}
resource apiManagement_apiName_operation_addPerson 'Microsoft.ApiManagement/service/apis/operations@2021-08-01' = {
  parent: apiManagement_apiName
  name: operation_addPerson

  dependsOn: [
    apiManagement_apiName_apiSchemaGuid
  ]
  properties: {
    request: {
      headers: [
        {
          name: 'Content-Type'
          type: 'string'
          required: true
          values: [
            'application/json'
          ]
        }
      ]
      representations: [
        {
          contentType: 'application/json'
          schemaId: apiSchemaGuid
          typeName: 'Definition_Person'
        }
      ]
    }
    displayName: 'Add Person'
    description: 'Add Person Information to ServiceBus. \nThe Request Body is parsed to ensure correct schema.'
    method: 'POST'
    urlTemplate: '/${serviceBusQueueName1}/messages'
  }
}

resource serviceName_apiName_policy 'Microsoft.ApiManagement/service/apis/policies@2021-08-01' = {
  parent: apiManagement_apiName
  name: 'policy'
  properties: {
    value: '<!-- All operations-->\r\n<policies>\r\n  <inbound>\r\n    <base/>\r\n    <set-backend-service base-url="${serviceBusEndpoint}" />\r\n  <set-header name="Content-Type" exists-action="override">\r\n  <value>application/json</value>\r\n  </set-header>\r\n  </inbound>\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <outbound>\r\n    <base />\r\n  </outbound>\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'rawxml'
  }
}
resource apiManagement_apiName_operation_addPerson_policy 'Microsoft.ApiManagement/service/apis/operations/policies@2021-08-01' = {
  parent: apiManagement_apiName_operation_addPerson
  name: 'policy'
  properties: {
    value: personPolicy
    format: 'rawxml'
  }
}
