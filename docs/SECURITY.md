# Security Guide

This document outlines the security features and best practices for the OpenClaw on Azure deployment.

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Internet                                     │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ HTTPS Only (443)
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Azure Bastion                                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ • Browser-based SSH/RDP                                     │    │
│  │ • No public IP on VM                                        │    │
│  │ • Session recording available                               │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ Private Network (10.0.x.x)
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Virtual Network (Isolated)                                          │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Network Security Group                                     │    │
│  │  • Default Deny All Inbound                                 │    │
│  │  • Only Bastion-to-VM traffic allowed                       │    │
│  │  • Outbound to Azure services only                          │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                  │                                   │
│                                  ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Virtual Machine                                            │    │
│  │  • No public IP address                                     │    │
│  │  • Managed Identity for authentication                      │    │
│  │  • Encrypted OS disk                                        │    │
│  │  • Auto-patching enabled                                    │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ Managed Identity Auth (No Keys!)
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Azure AI Foundry                                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ • RBAC-controlled access                                    │    │
│  │ • Audit logging enabled                                     │    │
│  │ • Token-based authentication                                │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Security Features

### 1. Network Isolation

**No Public IP Address**
- The VM has no public IP address
- Cannot be accessed directly from the internet
- All access is through Azure Bastion

**Network Security Group (NSG)**
- Default deny all inbound traffic
- Explicit rules for Bastion communication only
- Logging enabled for audit trails

**Virtual Network Isolation**
- Dedicated VNet for OpenClaw workloads
- Subnet segmentation (Default, Bastion)
- Private IP addressing (10.0.0.0/16)

### 2. Secure Access via Azure Bastion

Azure Bastion provides:
- **Browser-based access**: No RDP/SSH client needed
- **TLS encryption**: All traffic encrypted in transit
- **No exposed ports**: SSH (22) and RDP (3389) not exposed
- **Session recording**: Available with Premium SKU
- **Azure AD authentication**: SSO support

### 3. Managed Identity Authentication

Instead of storing API keys or secrets:
- **User Assigned Managed Identity** is created
- Identity is granted minimal required permissions
- No secrets to rotate or manage
- Automatic token management

**Required Role Assignment:**
```
Role: Cognitive Services OpenAI User
Scope: Azure AI Foundry resource
Principal: VM's Managed Identity
```

### 4. Encryption

**Disk Encryption**
- OS disk encrypted with platform-managed keys
- Can be upgraded to customer-managed keys (CMK)

**In-Transit Encryption**
- All Bastion connections use TLS 1.2+
- Azure AI Foundry API calls use HTTPS

### 5. Automatic Patching

- Linux automatic patching enabled
- Security updates applied automatically
- Reboot policy: "IfRequired"

### 6. Auto-Shutdown

- VM configured to shutdown at 7 PM UTC
- Reduces attack surface when not in use
- Can be configured for your timezone

## Security Best Practices

### Before Deployment

1. **Review Bicep templates** for any custom modifications
2. **Choose a strong admin password** (min 12 chars, complex)
3. **Consider SSH keys** instead of passwords for production
4. **Plan your network** if integrating with existing infrastructure

### After Deployment

1. **Grant minimal permissions** to the Managed Identity
   ```bash
   # Grant only the required role
   az role assignment create \
     --assignee <MANAGED_IDENTITY_PRINCIPAL_ID> \
     --role "Cognitive Services OpenAI User" \
     --scope <AI_FOUNDRY_RESOURCE_ID>
   ```

2. **Enable Azure Defender** for additional protection
   ```bash
   az security pricing create \
     --name VirtualMachines \
     --tier Standard
   ```

3. **Review Activity Logs** regularly
   - Azure Portal > Monitor > Activity Log
   - Set up alerts for suspicious activity

4. **Rotate admin password** periodically
   ```bash
   az vm user update \
     --resource-group <RG_NAME> \
     --name <VM_NAME> \
     --username <ADMIN_USER> \
     --password <NEW_PASSWORD>
   ```

### Operational Security

1. **Don't store secrets in code**
   - Use Azure Key Vault for any additional secrets
   - Environment variables for configuration

2. **Regular updates**
   - Keep Docker images updated
   - Review and apply OS patches

3. **Monitor resource access**
   - Review Bastion connection logs
   - Set up alerts for failed login attempts

4. **Backup configuration**
   - Use Azure Backup for VM data
   - Export critical configurations

## Compliance Considerations

### Data Residency

- All resources deployed in a single Azure region
- Data stays within the chosen region
- AI Foundry may have specific regional constraints

### Audit Logging

Enabled by default:
- Azure Activity Logs (control plane)
- Azure Bastion connection logs
- VM boot diagnostics

For enhanced logging, enable:
- Azure Monitor Logs
- Log Analytics Workspace

### Access Control

Use Azure RBAC for access control:

| Role | Access Level |
|------|--------------|
| Owner | Full access |
| Contributor | Create/manage resources |
| Reader | View only |
| Custom | Define specific permissions |

## Security Hardening Checklist

- [ ] Review and customize NSG rules
- [ ] Enable Azure Defender for servers
- [ ] Configure Azure Monitor alerts
- [ ] Set up backup policy
- [ ] Enable disk encryption (if not using default)
- [ ] Review and limit Managed Identity permissions
- [ ] Configure Azure Policy for compliance
- [ ] Enable Azure AD authentication for Bastion (Premium)
- [ ] Set up Azure Sentinel for SIEM (optional)
- [ ] Configure network watcher for traffic analysis

## Incident Response

### Suspected Compromise

1. **Isolate the VM**
   ```bash
   # Disable network interface
   az network nic update \
     --resource-group <RG_NAME> \
     --name <NIC_NAME> \
     --network-security-group ""
   ```

2. **Stop the VM**
   ```bash
   az vm stop --resource-group <RG_NAME> --name <VM_NAME>
   ```

3. **Preserve evidence**
   - Create disk snapshot
   - Export Activity Logs

4. **Investigate**
   - Review Bastion logs
   - Check AI Foundry usage
   - Analyze VM logs

5. **Remediate and recover**
   - Rotate all credentials
   - Redeploy from clean template if needed

## Contact

For security concerns or vulnerabilities, please:
1. Open a private security advisory on GitHub
2. Do not disclose publicly until addressed
