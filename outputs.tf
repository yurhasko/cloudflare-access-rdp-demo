output "rdp_vm_username" {
  description = "The username for the RDP VM"
  value       = module.cf_rdp_vm.admin_username
}

output "rdp_vm_password" {
  description = "The password of the RDP VM"
  value       = nonsensitive(module.cf_rdp_vm.admin_password)
}

output "cloudflare_browser_rdp_url" {
  description = "The URL to access the RDP VM via Cloudflare Browser RDP"
  value       = "https://${cloudflare_dns_record.rdp_fqdn.name}.${data.cloudflare_zone.current_zone.name}/rdp/${data.cloudflare_zero_trust_tunnel_cloudflared_virtual_networks.default_cloudflared_vnet.result[0].id}/${module.cf_rdp_vm.virtual_machine_azurerm.private_ip_address}/3389"
}