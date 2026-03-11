// Licensed under the Apache License, Version 2.0

using '../main.bicep'

param environment = 'dev'
param publisherEmail = 'admin@healthcaredemo.com'
param publisherName = 'Healthcare Referral Demo'
param alertEmailAddress = 'admin@healthcaredemo.com'
param vnetAddressPrefix = '10.0.0.0/16'
// AzureConnectors.EastUS2 service tag IPs — allows Logic Apps managed connectors through SB firewall
param connectorOutboundIpRanges = [
  '20.85.69.38/32'
  '20.85.69.62/32'
  '20.85.80.197/32'
  '20.85.81.137/32'
  '20.98.192.80/28'
  '20.98.192.96/27'
  '40.70.146.208/28'
  '40.70.151.96/27'
  '52.179.236.41/32'
  '52.184.245.14/32'
  '52.225.129.144/32'
  '52.232.188.154/32'
  '104.209.247.23/32'
  '104.210.14.156/32'
]
