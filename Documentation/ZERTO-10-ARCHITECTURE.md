# Zerto 10.x Architecture Changes

## Port Configuration

### ✅ Zerto 10.x (Linux ZVMA)
The tool is **fully compatible** with Zerto 10.x. The architecture uses:

- **Port 443 (HTTPS)** - All API access and GUI
- **Keycloak Authentication** - Modern OAuth2/OIDC authentication
- **Unified Endpoint** - Both GUI and REST API through same port

**No port 9669 required!** The tool automatically uses `https://<zvma-host>/` which defaults to port 443.

### 📜 Zerto 9.x and Earlier (Windows ZVM)
Legacy architecture (still supported):

- **Port 9669** - REST API
- **Port 9070/9071** - GUI
- **Session-based Auth** - x-zerto-session headers

## How the Tool Adapts

The script automatically detects and works with both architectures:

```powershell
# Script uses hostname without port specification
$baseUri = "https://$ZVMAHost/"

# API discovery checks these endpoints in order:
# Zerto 10.x endpoints:
"https://$ZVMAHost/openapi/v1.json"
"https://$ZVMAHost/swagger/v1/swagger.json"

# Zerto 9.x endpoints:
"https://$ZVMAHost/swagger/swagger.json"
```

When no port is specified in the URL, HTTPS defaults to **port 443**.

## Keycloak Authentication (Zerto 10.x)

The tool uses Keycloak OAuth2 password grant flow:

1. **POST** to `https://<zvma>/auth/realms/zerto/protocol/openid-connect/token`
2. Receives **access_token** (JWT)
3. Uses token in `Authorization: Bearer <token>` header
4. All API calls: `https://<zvma>/v1/...`

## Network Requirements

### Firewall Rules

**For Zerto 10.x Linux:**
```
Source: Compliance Tool Machine
Destination: ZVMA IP/Hostname
Port: 443 (HTTPS)
Direction: Outbound
```

**For Zerto 9.x Windows (Legacy):**
```
Source: Compliance Tool Machine
Destination: ZVM IP/Hostname
Port: 9669 (HTTPS)
Direction: Outbound
```

### Testing Connectivity

**Zerto 10.x:**
```powershell
Test-NetConnection -ComputerName <zvma-host> -Port 443
```

**Zerto 9.x:**
```powershell
Test-NetConnection -ComputerName <zvm-host> -Port 9669
```

## API Endpoint Examples

### Zerto 10.x (Linux)
```
https://zvma.example.com/auth/realms/zerto/protocol/openid-connect/token
https://zvma.example.com/v1/localsite
https://zvma.example.com/v1/vpgs
https://zvma.example.com/v1/vms
https://zvma.example.com/openapi/v1.json
```

### Zerto 9.x (Windows)
```
https://zvm.example.com:9669/v1/session/add
https://zvm.example.com:9669/v1/localsite
https://zvm.example.com:9669/v1/vpgs
https://zvm.example.com:9669/v1/vms
https://zvm.example.com:9669/swagger/swagger.json
```

## Tool Configuration

### GUI Configuration
In the Zerto Compliance Launcher:

1. **Source Site:** Enter ZVMA hostname or IP
   - ✅ Zerto 10.x: `zvma-10x.example.com` or `10.0.1.100`
   - ✅ Zerto 9.x: `zvm-9x.example.com` or `10.0.1.50`
   
2. **No port specification needed** - Tool auto-detects

3. **Lab Mode:** Check for self-signed certificates (both versions)

### PowerShell Direct Execution

**Zerto 10.x:**
```powershell
.\ZertoComplianceNew.ps1 `
    -ZVMAHost "zvma-10x.example.com" `
    -Username "admin" `
    -Password "YourPassword"
```

**Zerto 9.x:**
```powershell
.\ZertoComplianceNew.ps1 `
    -ZVMAHost "zvm-9x.example.com" `
    -Username "administrator@vsphere.local" `
    -Password "YourPassword"
```

Both commands are identical - the script handles version differences automatically!

## SSL/TLS Considerations

### Zerto 10.x
- Uses system-installed certificates
- Self-signed certificates common in lab environments
- Lab Mode checkbox disables SSL verification for testing

### Zerto 9.x
- Same SSL considerations
- Lab Mode works for both versions

## Version Detection

The tool doesn't explicitly check Zerto version. Instead, it:

1. Attempts Keycloak authentication (Zerto 10.x method)
2. If that fails, falls back to session-based auth (Zerto 9.x method)
3. Uses API discovery to find available endpoints
4. Adapts to whatever responds successfully

This makes the tool **version-agnostic** and **future-proof**.

## Summary

✅ **Port 443** - Used by Zerto 10.x (current architecture)  
📜 **Port 9669** - Used by Zerto 9.x and earlier (legacy)  
🔄 **Tool auto-detects** - No manual configuration needed  
🌐 **Hostname only** - Don't specify ports in the GUI  
🔒 **Lab Mode** - Handles self-signed certificates for both versions  

---

**Documentation Updated:** December 25, 2025  
**Applies to:** Zerto Compliance Tool v2.1.0+  
**Contact:** aaron.lastoff@hpe.com
