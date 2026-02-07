# Troubleshooting Guide

This guide helps you resolve common issues with the OpenClaw on Azure deployment.

## Table of Contents

- [Deployment Issues](#deployment-issues)
- [Connection Issues](#connection-issues)
- [Azure AI Foundry Issues](#azure-ai-foundry-issues)
- [OpenClaw Issues](#openclaw-issues)
- [Performance Issues](#performance-issues)
- [Cost Issues](#cost-issues)

---

## Deployment Issues

### ❌ "InsufficientQuota" Error

**Symptoms:**
```
Code: InsufficientQuota
Message: Operation could not be completed as it results in exceeding approved quota
```

**Solutions:**

1. **Check your quota:**
   ```bash
   az vm list-usage --location eastus2 --output table
   ```

2. **Try a different region:**
   ```bash
   ./deploy.ps1 -ResourceGroupName "rg-openclaw" -Location "westus2"
   ```

3. **Request quota increase:**
   - Go to Azure Portal > Subscriptions > Usage + quotas
   - Request increase for the VM family

4. **Use a smaller VM size:**
   Modify `vmSize` parameter to `Standard_B2s` (burstable, cheaper)

### ❌ "ResourceGroupNotFound" Error

**Symptoms:**
```
Code: ResourceGroupNotFound
Message: Resource group 'rg-openclaw' could not be found
```

**Solution:**
The script should create the resource group automatically. If it fails:
```bash
az group create --name rg-openclaw --location eastus2
```

### ❌ "InvalidTemplateDeployment" Error

**Symptoms:**
```
Code: InvalidTemplateDeployment
Message: The template deployment failed because of policy violation
```

**Solutions:**

1. **Check Azure Policy:**
   - Go to Azure Portal > Policy > Assignments
   - Look for policies that might block the deployment
   
2. **Common policy blockers:**
   - Public IP restrictions
   - VM size restrictions
   - Region restrictions

3. **Contact your Azure administrator** to request exemptions

### ❌ Password Validation Failed

**Symptoms:**
```
The supplied password must be between 12-123 characters long and must satisfy at least 3 of password complexity requirements
```

**Solution:**
Use a password that meets Azure requirements:
- Minimum 12 characters
- Contains uppercase letter
- Contains lowercase letter
- Contains number
- Contains special character

Example: `OpenClaw2024!Secure`

---

## Connection Issues

### ❌ Cannot Connect via Bastion

**Symptoms:**
- Bastion connection times out
- "Unable to connect" error

**Solutions:**

1. **Check Bastion deployment status:**
   ```bash
   az network bastion show \
     --name bastion-openclaw-dev \
     --resource-group rg-openclaw \
     --query provisioningState
   ```

2. **Verify VM is running:**
   ```bash
   az vm show \
     --resource-group rg-openclaw \
     --name vm-openclaw-dev \
     --query powerState
   ```

3. **Start the VM if stopped:**
   ```bash
   az vm start --resource-group rg-openclaw --name vm-openclaw-dev
   ```

4. **Check NSG rules:**
   - Bastion subnet NSG must allow required ports
   - Default subnet NSG must allow Bastion traffic

5. **Wait for provisioning:**
   - Bastion can take up to 10 minutes to fully provision
   - VM cloud-init can take 5-10 minutes

### ❌ Bastion Session Disconnects

**Symptoms:**
- Session drops after a few minutes
- "Connection timed out" messages

**Solutions:**

1. **Keep session active:**
   - Don't leave the session idle for long periods
   - Default timeout is 30 minutes

2. **Check browser:**
   - Use a supported browser (Chrome, Edge, Firefox)
   - Disable browser extensions that might interfere

3. **Network issues:**
   - Check your local network connection
   - Try from a different network

### ❌ SSH Key Authentication Failed

**Symptoms:**
```
Permission denied (publickey)
```

**Solution:**
The default template uses password authentication. If you configured SSH keys:

1. Ensure the public key was correctly added to `~/.ssh/authorized_keys`
2. Check key permissions:
   ```bash
   chmod 600 ~/.ssh/authorized_keys
   chmod 700 ~/.ssh
   ```

---

## Azure AI Foundry Issues

### ❌ Managed Identity Token Failed

**Symptoms:**
```
❌ Could not get Managed Identity token
```

**Solutions:**

1. **Verify Managed Identity is assigned:**
   ```bash
   az vm identity show \
     --resource-group rg-openclaw \
     --name vm-openclaw-dev
   ```

2. **Check role assignment:**
   ```bash
   az role assignment list \
     --assignee <MANAGED_IDENTITY_PRINCIPAL_ID> \
     --output table
   ```

3. **Grant required role:**
   ```bash
   az role assignment create \
     --assignee <PRINCIPAL_ID> \
     --role "Cognitive Services OpenAI User" \
     --scope <AI_FOUNDRY_RESOURCE_ID>
   ```

4. **Wait for propagation:**
   Role assignments can take up to 5 minutes to propagate

### ❌ "401 Unauthorized" from AI Foundry

**Symptoms:**
```
Error: 401 Unauthorized
```

**Solutions:**

1. **Verify endpoint URL:**
   - Should be `https://<resource-name>.openai.azure.com/`
   - No trailing slash issues

2. **Check deployment name:**
   - Use the exact deployment name from AI Foundry
   - Not the model name (e.g., `gpt-5-deployment` not `gpt-5`)

3. **Verify role assignment:**
   - Ensure "Cognitive Services OpenAI User" role is assigned
   - Ensure it's on the correct AI Foundry resource

### ❌ "404 Not Found" from AI Foundry

**Symptoms:**
```
Error: 404 Resource not found
```

**Solutions:**

1. **Check endpoint URL:**
   ```bash
   curl https://your-resource.openai.azure.com/openai/deployments?api-version=2024-02-01 \
     -H "Authorization: Bearer $(az account get-access-token --resource https://cognitiveservices.azure.com/ --query accessToken -o tsv)"
   ```

2. **Verify deployment exists:**
   - Go to Azure AI Foundry portal
   - Check Deployments section
   - Ensure model is deployed and active

### ❌ Model Quota Exceeded

**Symptoms:**
```
Error: 429 Rate limit exceeded
```

**Solutions:**

1. **Check your quota:**
   - Azure AI Foundry portal > Quotas
   
2. **Implement retry logic** in your application

3. **Request quota increase:**
   - Azure Portal > AI Foundry > Quotas > Request increase

---

## OpenClaw Issues

### ❌ Docker Not Running

**Symptoms:**
```
Cannot connect to the Docker daemon
```

**Solutions:**

1. **Check Docker status:**
   ```bash
   sudo systemctl status docker
   ```

2. **Start Docker:**
   ```bash
   sudo systemctl start docker
   ```

3. **Add user to docker group:**
   ```bash
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

### ❌ OpenClaw Not Found

**Symptoms:**
```
bash: cd: /home/user/openclaw: No such file or directory
```

**Solutions:**

1. **Check if cloud-init completed:**
   ```bash
   sudo cat /var/log/cloud-init-output.log | tail -50
   ```

2. **Check OpenClaw location:**
   ```bash
   ls -la /opt/openclaw
   ```

3. **Re-clone if necessary:**
   ```bash
   git clone https://github.com/openclaw/openclaw.git ~/openclaw
   ```

### ❌ Docker Compose Errors

**Symptoms:**
```
ERROR: Couldn't connect to Docker daemon
```

**Solutions:**

1. **Use new Docker Compose syntax:**
   ```bash
   docker compose up -d  # Not docker-compose
   ```

2. **Check Docker Compose plugin:**
   ```bash
   docker compose version
   ```

3. **Reinstall if needed:**
   ```bash
   sudo apt-get update
   sudo apt-get install docker-compose-plugin
   ```

---

## Performance Issues

### ❌ VM Running Slowly

**Solutions:**

1. **Check resource usage:**
   ```bash
   htop
   ```

2. **Check disk space:**
   ```bash
   df -h
   ```

3. **Resize VM:**
   ```bash
   az vm resize \
     --resource-group rg-openclaw \
     --name vm-openclaw-dev \
     --size Standard_D4s_v5
   ```

4. **Clear Docker resources:**
   ```bash
   docker system prune -af
   ```

### ❌ High Latency to AI Foundry

**Solutions:**

1. **Check region alignment:**
   - Deploy VM in the same region as AI Foundry

2. **Check network path:**
   ```bash
   traceroute your-resource.openai.azure.com
   ```

3. **Consider Private Endpoints** for production workloads

---

## Cost Issues

### ❌ Unexpected High Costs

**Common causes:**

1. **Azure Bastion running 24/7:**
   - ~$140/month for Standard SKU
   - Consider deleting when not in use
   - Or use Developer SKU (free for limited use)

2. **VM running continuously:**
   - Enable auto-shutdown
   - Stop VM when not in use

3. **Check for orphaned resources:**
   ```bash
   az resource list --resource-group rg-openclaw --output table
   ```

### ❌ Cost Optimization Tips

1. **Use spot VMs** for dev/test:
   ```bicep
   priority: 'Spot'
   evictionPolicy: 'Deallocate'
   ```

2. **Schedule start/stop:**
   - Use Azure Automation
   - Or manual start/stop

3. **Right-size the VM:**
   - Start with Standard_B2s for testing
   - Scale up only if needed

4. **Delete Bastion when not needed:**
   ```bash
   az network bastion delete \
     --name bastion-openclaw-dev \
     --resource-group rg-openclaw
   ```

---

## Getting Help

If you can't resolve your issue:

1. **Check existing issues:**
   [GitHub Issues](https://github.com/YOUR_USERNAME/sample-OpenClaw-on-Azure-with-AI-Foundry/issues)

2. **Open a new issue** with:
   - Error message (full text)
   - Steps to reproduce
   - Environment details (region, VM size, etc.)
   - Relevant logs

3. **Azure Support:**
   - [Azure Support](https://azure.microsoft.com/support/)
   - Check Azure Status page for service issues

4. **OpenClaw Support:**
   - [OpenClaw GitHub](https://github.com/openclaw/openclaw)
