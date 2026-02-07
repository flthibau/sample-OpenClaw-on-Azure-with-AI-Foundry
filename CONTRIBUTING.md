# Contributing to OpenClaw on Azure

Thank you for your interest in contributing to this project! This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Submitting Changes](#submitting-changes)
- [Coding Standards](#coding-standards)
- [Testing](#testing)

## Code of Conduct

This project follows the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the bug report template
3. Include:
   - Clear description of the issue
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (Azure region, VM size, etc.)
   - Relevant logs or error messages

### Suggesting Features

1. Check existing feature requests
2. Open an issue with:
   - Clear description of the feature
   - Use case and benefits
   - Potential implementation approach

### Pull Requests

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Development Setup

### Prerequisites

- Azure subscription
- Azure CLI installed
- Bicep CLI (included with Azure CLI)
- PowerShell 7+ or Bash

### Local Testing

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/sample-OpenClaw-on-Azure-with-AI-Foundry.git
   cd sample-OpenClaw-on-Azure-with-AI-Foundry
   ```

2. **Validate Bicep templates:**
   ```bash
   az bicep build --file infra/main.bicep
   ```

3. **Run what-if deployment:**
   ```bash
   az deployment group create \
     --resource-group rg-openclaw-test \
     --template-file infra/main.bicep \
     --parameters vmAdminPassword="YourSecurePassword123!" \
     --what-if
   ```

## Submitting Changes

### Branch Naming

Use descriptive branch names:
- `feature/add-private-endpoint`
- `bugfix/fix-nsg-rules`
- `docs/update-readme`

### Commit Messages

Follow conventional commits:
```
type(scope): description

[optional body]
[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

Examples:
```
feat(infra): add Azure Private Endpoint for AI Foundry
fix(security): update NSG rules for Bastion connectivity
docs(readme): add cost estimation section
```

### Pull Request Process

1. Ensure all tests pass
2. Update documentation if needed
3. Request review from maintainers
4. Address feedback
5. Squash and merge when approved

## Coding Standards

### Bicep

Follow [Bicep best practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices):

- Use camelCase for parameters, variables, and outputs
- Use descriptive names
- Add `@description` decorators to all parameters
- Use `@secure()` for sensitive values
- Group related resources with comments
- Use symbolic references instead of `resourceId()`

Example:
```bicep
@description('The Azure region for all resources')
param location string = resourceGroup().location

@secure()
@description('Administrator password for the VM')
param vmAdminPassword string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-example'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
  }
}
```

### Shell Scripts

- Add shebang line
- Use shellcheck for linting
- Quote variables
- Handle errors with `set -e`
- Add helpful comments

### PowerShell

- Follow [PowerShell Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines)
- Use approved verbs
- Add comment-based help
- Use `$ErrorActionPreference = 'Stop'`

## Testing

### Bicep Validation

```bash
# Syntax check
az bicep build --file infra/main.bicep

# Linting (using Bicep linter rules)
az bicep lint --file infra/main.bicep
```

### Security Scanning

```bash
# Install Checkov
pip install checkov

# Scan Bicep files
checkov -f infra/main.bicep --framework bicep
```

### Integration Testing

For full integration tests:

1. Deploy to a test resource group
2. Verify all resources created
3. Test Bastion connectivity
4. Clean up resources

```bash
# Deploy
./scripts/deploy.sh -g rg-openclaw-test -l eastus2 -n test

# Clean up
az group delete --name rg-openclaw-test --yes --no-wait
```

## Questions?

If you have questions, please:
1. Check the [documentation](docs/)
2. Search existing issues
3. Open a new issue with your question

Thank you for contributing!
