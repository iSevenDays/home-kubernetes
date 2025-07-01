package config

import (
	"net"
)

#Config: {
	node_cidr: net.IPCIDR & !=cluster_pod_cidr & !=cluster_svc_cidr
	node_dns_servers?: [...net.IPv4]
	node_ntp_servers?: [...net.IPv4]
	node_default_gateway?: net.IPv4 & !=""
	node_vlan_tag?: string & !=""
	cluster_pod_cidr: *"10.42.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_svc_cidr
	cluster_svc_cidr: *"10.43.0.0/16" | net.IPCIDR & !=node_cidr & !=cluster_pod_cidr
	cluster_api_addr: net.IPv4
	cluster_api_tls_sans?: [...net.FQDN]
	cluster_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_dns_gateway_addr & !=cloudflare_gateway_addr
	cluster_dns_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cloudflare_gateway_addr
	repository_name: string
	repository_branch?: string & !=""
	repository_visibility?: *"public" | "private"
	cloudflare_domain: net.FQDN
	cloudflare_token: string
	cloudflare_gateway_addr: net.IPv4 & !=cluster_api_addr & !=cluster_gateway_addr & !=cluster_dns_gateway_addr
	cilium_bgp_router_addr?: net.IPv4 & !=""
	cilium_bgp_router_asn?: string & !=""
	cilium_bgp_node_asn?: string & !=""
	cilium_loadbalancer_mode?: *"dsr" | "snat"
	openhands_global_secret?: string & !=""
	litellm_team_id?: string & !=""
	litellm_model?: string & !=""
	litellm_base_url?: string & !=""
	litellm_api_key?: string & !=""
	litellm_timeout?: int & !=0
	litellm_max_output_tokens?: int & !=0
	litellm_context_window?: int & !=0
	openhands_pg_password?: string & !=""
	openhands_redis_password?: string & !=""
	docker_username?: string & !=""
	docker_password?: string & !=""
	ghcr_username?: string & !=""
	ghcr_pat?: string & !=""
	github_app_id?: int & !=0
	github_app_private_key?: string & !=""
	github_client_id?: string & !=""
	github_client_secret?: string & !=""
	github_webhook_secret?: string & !=""
}

#Config
