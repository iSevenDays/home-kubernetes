#!/bin/bash

# Infrastructure Health Check Script
# Based on checklist.md - Run after every deployment to verify nothing is broken

# Remove set -e to allow script to continue after individual test failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

# Helper functions
log_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASS++))
}

log_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAIL++))
}

log_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((WARN++))
}

log_info() {
    echo -e "${BLUE}ℹ️  INFO${NC}: $1"
}

# Test function with timeout
test_url() {
    local url="$1"
    local expected_server="$2"
    local timeout=10
    
    log_info "Testing: $url"
    
    if response=$(curl -I --max-time $timeout "$url" 2>&1); then
        if echo "$response" | grep -q "HTTP/[12].[01] 200\|HTTP/[12].[01] 302"; then
            if [ -n "$expected_server" ]; then
                if echo "$response" | grep -i "server:" | grep -q "$expected_server"; then
                    log_pass "$url → $(echo "$response" | grep -i "server:" | head -1 | tr -d '\r')"
                else
                    log_warn "$url → Wrong server: $(echo "$response" | grep -i "server:" | head -1 | tr -d '\r') (expected: $expected_server)"
                fi
            else
                log_pass "$url → $(echo "$response" | head -1 | tr -d '\r')"
            fi
        else
            log_fail "$url → $(echo "$response" | head -1 | tr -d '\r')"
        fi
    else
        log_fail "$url → Connection failed: $(echo "$response" | tail -1)"
    fi
}

# Test DNS resolution
test_dns() {
    local domain="$1"
    local expected_type="$2"  # "tunnel" or "direct" or "custom"
    
    log_info "Testing DNS: $domain"
    
    # Try dig first, then fallback to nslookup
    if result=$(dig +short "$domain" 2>/dev/null); then
        if [ -n "$result" ]; then
            dns_source="dig"
        else
            # Fallback to nslookup if dig returns empty
            if nslookup_result=$(nslookup "$domain" 2>/dev/null | grep -A 100 "Non-authoritative answer:" | grep "Address:" | cut -d' ' -f2); then
                result="$nslookup_result"
                dns_source="nslookup"
            fi
        fi
    else
        # Try nslookup as fallback
        if nslookup_result=$(nslookup "$domain" 2>/dev/null | grep -A 100 "Non-authoritative answer:" | grep "Address:" | cut -d' ' -f2); then
            result="$nslookup_result"
            dns_source="nslookup"
        fi
    fi
    
    if [ -n "$result" ]; then
        case "$expected_type" in
            "tunnel")
                if echo "$result" | grep -q "cfargotunnel.com"; then
                    log_pass "$domain → Tunnel: $(echo "$result" | head -1)"
                else
                    log_warn "$domain → Not tunnel: $result"
                fi
                ;;
            "direct")
                if echo "$result" | grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"; then
                    log_pass "$domain → Direct IP: $(echo "$result" | tr '\n' ' ' | head -c 50)"
                else
                    log_warn "$domain → Not direct IP: $result"
                fi
                ;;
            *)
                log_pass "$domain → $result"
                ;;
        esac
    else
        log_fail "$domain → No DNS response"
    fi
}

# Test Kubernetes resources
test_k8s_resource() {
    local resource="$1"
    local namespace="$2"
    local name="$3"
    
    log_info "Testing K8s: $resource/$name in $namespace"
    
    if kubectl get "$resource" -n "$namespace" "$name" &>/dev/null; then
        if [ "$resource" = "httproute" ]; then
            # HTTPRoutes have status per parent, check if any parent is accepted
            if accepted=$(kubectl get "$resource" -n "$namespace" "$name" -o jsonpath='{.status.parents[?(@.conditions[?(@.type=="Accepted" && @.status=="True")])].parentRef.name}' 2>/dev/null); then
                if [ -n "$accepted" ]; then
                    log_pass "K8s $resource/$name → Accepted by gateway: $accepted"
                else
                    log_fail "K8s $resource/$name → Not accepted by any gateway"
                fi
            else
                log_warn "K8s $resource/$name → No status information"
            fi
        else
            # Other resources use standard Ready condition
            if status=$(kubectl get "$resource" -n "$namespace" "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); then
                if [ "$status" = "True" ]; then
                    log_pass "K8s $resource/$name → Ready"
                else
                    log_fail "K8s $resource/$name → Not Ready (status: $status)"
                fi
            else
                log_warn "K8s $resource/$name → Status unknown"
            fi
        fi
    else
        log_fail "K8s $resource/$name → Not found"
    fi
}

# Test external-DNS logs
test_external_dns() {
    log_info "Testing external-DNS health"
    
    if kubectl get deployment -n network cloudflare-dns &>/dev/null; then
        if logs=$(kubectl logs -n network deployment/cloudflare-dns --tail=10 2>/dev/null); then
            if echo "$logs" | grep -q "level=fatal\|Failed to submit all changes"; then
                log_fail "External-DNS → Fatal errors in logs"
                echo "$logs" | grep "level=fatal\|Failed to submit all changes" | tail -2
            elif echo "$logs" | grep -q "level=error"; then
                log_warn "External-DNS → Error messages in logs"
                echo "$logs" | grep "level=error" | tail -2
            else
                log_pass "External-DNS → No fatal errors"
            fi
        else
            log_fail "External-DNS → Cannot retrieve logs"
        fi
    else
        log_fail "External-DNS → Deployment not found"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║             INFRASTRUCTURE HEALTH CHECK         ║${NC}"
    echo -e "${BLUE}║                  $(date '+%Y-%m-%d %H:%M:%S')                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo

    # 1. Service Connectivity Tests
    echo -e "${BLUE}🌐 SERVICE CONNECTIVITY TESTS${NC}"
    echo "----------------------------------------"
    test_url "https://openhands.sevendays.cloud" "cloudflare"
    test_url "https://llm-proxy.sevendays.cloud" "cloudflare"
    test_url "https://flux-webhook.sevendays.cloud" "cloudflare"
    test_url "http://auth.openhands.sevendays.cloud" "cloudflare"
    echo

    # 2. DNS Resolution Tests
    echo -e "${BLUE}🔍 DNS RESOLUTION TESTS${NC}"
    echo "----------------------------------------"
    test_dns "openhands.sevendays.cloud" "direct"
    test_dns "llm-proxy.sevendays.cloud" "direct"
    test_dns "flux-webhook.sevendays.cloud" "direct"
    test_dns "auth.openhands.sevendays.cloud" "direct"
    echo

    # 3. Kubernetes Resources Tests
    echo -e "${BLUE}☸️  KUBERNETES RESOURCES TESTS${NC}"
    echo "----------------------------------------"
    test_k8s_resource "helmrelease" "network" "cloudflare-dns"
    test_k8s_resource "helmrelease" "openhands" "openhands"
    test_k8s_resource "httproute" "openhands" "openhands"
    test_k8s_resource "httproute" "openhands" "keycloak"
    test_k8s_resource "httproute" "openhands" "litellm-proxy"
    test_k8s_resource "httproute" "flux-system" "github-webhook"
    # test_k8s_resource "dnsendpoint" "openhands" "auth-openhands-override"  # Removed - using HTTPRoute now
    echo

    # 4. External-DNS Health
    echo -e "${BLUE}🔧 EXTERNAL-DNS HEALTH${NC}"
    echo "----------------------------------------"
    test_external_dns
    echo

    # 5. Summary
    echo -e "${BLUE}📊 SUMMARY${NC}"
    echo "========================================"
    echo -e "✅ PASSED: ${GREEN}$PASS${NC}"
    echo -e "⚠️  WARNINGS: ${YELLOW}$WARN${NC}"
    echo -e "❌ FAILED: ${RED}$FAIL${NC}"
    echo "========================================"

    if [ $FAIL -eq 0 ]; then
        if [ $WARN -eq 0 ]; then
            echo -e "${GREEN}🎉 ALL SYSTEMS OPERATIONAL${NC}"
            exit 0
        else
            echo -e "${YELLOW}⚠️  SYSTEMS OPERATIONAL WITH WARNINGS${NC}"
            exit 1
        fi
    else
        echo -e "${RED}🚨 CRITICAL ISSUES DETECTED${NC}"
        echo
        echo -e "${YELLOW}Quick fixes to try:${NC}"
        echo "1. Check external-DNS logs: kubectl logs -n network deployment/cloudflare-dns --tail=20"
        echo "2. Restart external-DNS: kubectl rollout restart -n network deployment/cloudflare-dns"
        echo "3. Check HTTPRoute status: kubectl get httproute -A"
        echo "4. Verify DNS propagation: dig +trace <failing-domain>"
        exit 2
    fi
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Infrastructure Health Check Script"
        echo ""
        echo "OPTIONS:"
        echo "  -h, --help     Show this help message"
        echo "  -v, --verbose  Verbose output (shows curl details)"
        echo "  -q, --quiet    Quiet mode (only show summary)"
        echo ""
        echo "Exit codes:"
        echo "  0 - All tests passed"
        echo "  1 - Tests passed with warnings"
        echo "  2 - Critical failures detected"
        exit 0
        ;;
    -v|--verbose)
        set -x
        ;;
    -q|--quiet)
        # Redirect info logs to /dev/null in quiet mode
        log_info() { :; }
        ;;
esac

# Run main function
main