# Infrastructure Change Checklist

## **CRITICAL: Always verify these items before AND after any DNS/networking changes**

### 🔴 **PRE-CHANGE VERIFICATION**

#### **1. Service Connectivity Baseline**
- [ ] `curl -I https://openhands.sevendays.cloud` → HTTP/2 200, server: cloudflare
- [ ] `curl -I https://llm-proxy.sevendays.cloud` → HTTP/2 200, server: cloudflare  
- [ ] `curl -I https://auth.openhands.sevendays.cloud` → Current status (document expected result)
- [ ] `curl -I https://flux-webhook.sevendays.cloud` → HTTP/2 200, server: cloudflare

#### **2. DNS Resolution Baseline**
- [ ] `dig +short openhands.sevendays.cloud` → Cloudflare tunnel CNAME
- [ ] `dig +short llm-proxy.sevendays.cloud` → Cloudflare tunnel CNAME  
- [ ] `dig +short auth.openhands.sevendays.cloud` → Document current resolution
- [ ] `dig +short flux-webhook.sevendays.cloud` → Cloudflare tunnel CNAME

#### **3. External-DNS Status**
- [ ] `kubectl get helmrelease -n network cloudflare-dns` → Ready: True
- [ ] `kubectl logs -n network deployment/cloudflare-dns --tail=5` → No fatal errors
- [ ] Document current external-DNS configuration flags

#### **4. HTTPRoute Status** 
- [ ] `kubectl get httproute -n openhands` → All Ready
- [ ] `kubectl get httproute -n default` → All Ready
- [ ] `kubectl get httproute -n flux-system` → All Ready

### 🟡 **DURING CHANGE**

#### **5. Change Scope Analysis**
- [ ] **IDENTIFY**: Which services should remain on Cloudflare tunnel?
- [ ] **IDENTIFY**: Which services should use direct Gateway access?
- [ ] **VERIFY**: Changes only affect intended services
- [ ] **DOCUMENT**: Expected DNS resolution changes for each service

#### **6. External-DNS Configuration Rules**
- [ ] **Global flags**: Only use `--cloudflare-proxied` if ALL services should be proxied
- [ ] **Per-service control**: Use annotations when mixing proxy/direct modes
- [ ] **Conflict prevention**: Exclude HTTPRoutes from external-DNS if using manual DNSEndpoints
- [ ] **Annotation verification**: `external-dns.alpha.kubernetes.io/controller: "ignore"` for exclusions

### 🟢 **POST-CHANGE VERIFICATION**

#### **7. Service Connectivity Check**
- [ ] `curl -I https://openhands.sevendays.cloud` → Still HTTP/2 200, server: cloudflare
- [ ] `curl -I https://llm-proxy.sevendays.cloud` → Still HTTP/2 200, server: cloudflare
- [ ] `curl -I https://auth.openhands.sevendays.cloud` → Expected result achieved
- [ ] `curl -I https://flux-webhook.sevendays.cloud` → Still HTTP/2 200, server: cloudflare

#### **8. DNS Resolution Verification**
- [ ] `dig +short openhands.sevendays.cloud` → Still Cloudflare tunnel CNAME  
- [ ] `dig +short llm-proxy.sevendays.cloud` → Still Cloudflare tunnel CNAME
- [ ] `dig +short auth.openhands.sevendays.cloud` → Expected resolution (Gateway IP or tunnel)
- [ ] `dig +short flux-webhook.sevendays.cloud` → Still Cloudflare tunnel CNAME

#### **9. External-DNS Health**
- [ ] `kubectl logs -n network deployment/cloudflare-dns --tail=10` → No fatal errors
- [ ] No "failed to submit all changes" messages
- [ ] All expected records created successfully

#### **10. End-to-End Testing**
- [ ] **Main App**: Can access OpenHands interface  
- [ ] **LLM Proxy**: Can access LLM endpoints
- [ ] **Auth Flow**: Can trigger OAuth (if that was the goal)
- [ ] **Flux Webhook**: Can receive GitHub webhooks

### ⚠️ **ROLLBACK CRITERIA**

#### **11. Immediate Rollback If:**
- [ ] Any main service (openhands, llm-proxy, flux-webhook) becomes inaccessible
- [ ] External-DNS shows fatal errors for more than 2 reconciliation cycles  
- [ ] DNS resolution fails for services that should remain on tunnel
- [ ] SSL certificate errors on previously working domains

#### **12. Rollback Process**
1. [ ] Revert external-DNS configuration (`--cloudflare-proxied` flag)
2. [ ] Remove problematic HTTPRoute annotations  
3. [ ] Delete manual DNSEndpoints if causing conflicts
4. [ ] Force external-DNS reconciliation: `kubectl rollout restart -n network deployment/cloudflare-dns`
5. [ ] Wait 2-3 minutes and re-verify all services

### 📋 **ARCHITECTURE RULES**

#### **13. Mixed Mode Best Practices**
- [ ] **Tunnel Services**: Use HTTPRoutes without exclusion annotations
- [ ] **Direct Gateway**: Use HTTPRoutes with `external-dns.alpha.kubernetes.io/controller: "ignore"` + manual DNSEndpoint
- [ ] **Never mix**: CNAME (HTTPRoute) and A record (DNSEndpoint) for same hostname
- [ ] **Global proxy flag**: Only when ALL services should be proxied

#### **14. Cloudflare Considerations**  
- [ ] **Free tier SSL**: Only covers `*.domain.com`, not `*.subdomain.domain.com`
- [ ] **Tunnel connectivity**: Requires proxied mode in Cloudflare
- [ ] **Direct Gateway**: Requires DNS-only mode in Cloudflare
- [ ] **Certificate management**: Let's Encrypt for direct Gateway, Cloudflare Universal SSL for tunnel

### 🚨 **EMERGENCY CONTACTS & COMMANDS**

#### **15. Quick Diagnosis**
```bash
# Service connectivity test
for svc in openhands llm-proxy flux-webhook; do 
  echo "=== $svc.sevendays.cloud ===" 
  curl -I https://$svc.sevendays.cloud 2>&1 | head -3
done

# DNS resolution check  
for svc in openhands llm-proxy auth.openhands flux-webhook; do
  echo "=== $svc.sevendays.cloud ===" 
  dig +short $svc.sevendays.cloud
done

# External-DNS status
kubectl logs -n network deployment/cloudflare-dns --tail=20
```

#### **16. Emergency Restore** 
```bash
# Restore global proxy mode (if all services were working before)
kubectl patch helmrelease cloudflare-dns -n network --type='json' \
  -p='[{"op": "add", "path": "/spec/values/extraArgs/-", "value": "--cloudflare-proxied"}]'

# Force reconciliation
kubectl rollout restart -n network deployment/cloudflare-dns
```

---

**⚠️ GOLDEN RULE: Test one service at a time, verify it works, then proceed to the next. Never change multiple services simultaneously.**