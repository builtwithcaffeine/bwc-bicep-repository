using 'main.bicep'

param location = ''
param locationShortCode = ''
param customerName = ''
param environmentType = ''
param deployedBy = ''

param logAnalyticsWorkspaceSkuName = 'PerGB2018'
param logAnalyticsWorkspaceRetentionInDays = 30

param enableAgwStorageStatus = true

param applicationGatewayEnableHttp2 = true
param applicationGatewaySku = 'WAF_v2'
param applicationGatewaySslPolicyType = 'Predefined'
param applicationGatewaySslPolicyName = 'AppGwSslPolicy20220101'

param defaultListenerHostName = 'demo.lab.builtwithcaffeine.cloud'
param defaultBackendFqdn = ''
param defaultBackendProtocol = 'Http'
param defaultBackendPort = 80
param defaultHealthProbePath = '/'
param defaultHealthProbeIntervalInSeconds = 30
param defaultHealthProbeTimeoutInSeconds = 30
param defaultHealthProbeUnhealthyThreshold = 3
param defaultRoutePriority = 100
