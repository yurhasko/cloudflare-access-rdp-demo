#########################################
#  locals for the Cloudflare RDP demo   #
#########################################
locals {
  environment      = "az-cf-rdp-demo"
  location         = "East US"
  enable_telemetry = false # All AVM modules have it enabled by default

  tags = {
    Project   = "az-cf-rdp-demo"
    ManagedBy = "Terraform"
  }

  windows_vm = {
    windows_hostname                            = "az-cf-rdp-vm"
    network_interface_name                      = "primary_nic_rdp_vm"
    network_security_group_name                 = "rdp_vm_nsg"
    network_security_group_nsg_association_name = "rdp_vm_nsg_association"
    vnet_address_space                          = "10.0.0.0/16"
    subnet_address_prefix                       = "10.0.1.0/24"
  }
}

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
  suffix  = ["${local.environment}"]
}

#########################################
#            Azure resources            #
#########################################
resource "azurerm_resource_group" "rdp_vm_rg" {
  name     = module.naming.resource_group.name_unique
  location = local.location
  tags     = local.tags
}

# NAT Gateway should be created before VNet to avoid dependency issues
module "natgateway" {
  source           = "Azure/avm-res-network-natgateway/azurerm"
  version          = "0.2.1"
  enable_telemetry = local.enable_telemetry

  name                = module.naming.nat_gateway.name_unique
  location            = azurerm_resource_group.rdp_vm_rg.location
  resource_group_name = azurerm_resource_group.rdp_vm_rg.name

  public_ips = {
    public_ip_1 = {
      name = "nat_gw_pip1"
    }
  }

  tags = local.tags
}

# Azure virtual network module for the RDP demo VM
module "rdp_vm_vnet" {
  source           = "Azure/avm-res-network-virtualnetwork/azurerm"
  version          = "0.9.1"
  enable_telemetry = local.enable_telemetry

  name                = module.naming.virtual_network.name_unique
  location            = local.location
  resource_group_name = azurerm_resource_group.rdp_vm_rg.name
  address_space       = [local.windows_vm.vnet_address_space]

  subnets = {
    main_subnet = {
      name             = module.naming.subnet.name_unique
      address_prefixes = [local.windows_vm.subnet_address_prefix]
      nat_gateway = {
        id = module.natgateway.resource_id
      }
    }
  }

  tags = local.tags

  depends_on = [
    azurerm_resource_group.rdp_vm_rg,
    module.natgateway
  ]
}

module "cf_rdp_vm" {
  source           = "Azure/avm-res-compute-virtualmachine/azurerm"
  version          = "0.19.3"
  enable_telemetry = local.enable_telemetry

  name                = module.naming.windows_virtual_machine.name
  computer_name       = local.windows_vm.windows_hostname
  location            = local.location
  resource_group_name = azurerm_resource_group.rdp_vm_rg.name
  zone                = "1"

  os_type  = "Windows"
  sku_size = var.windows_vm_size

  source_image_reference = var.windows_vm_image
  os_disk                = var.windows_vm_disk

  network_interfaces = {
    primary_nic = {
      name = module.naming.network_interface.name_unique
      ip_configurations = {
        internal = {
          name                          = "${module.naming.network_interface.name_unique}-ipconfig1"
          private_ip_subnet_resource_id = module.rdp_vm_vnet.subnets["main_subnet"].resource_id
        }
      }
    }
  }

  account_credentials = {
    admin_credentials = {
      username                           = var.windows_admin_username
      generate_admin_password_or_ssh_key = true
    }
  }

  managed_identities = {
    system_assigned = true
  }

  boot_diagnostics           = true
  enable_automatic_updates   = true
  provision_vm_agent         = true
  allow_extension_operations = true
  patch_mode                 = "AutomaticByPlatform"

  tags = local.tags
}

#########################################
#           Cloudflare resources        #
#########################################
resource "random_id" "cf_tunnel_secret" {
  byte_length = 32
}

data "cloudflare_zero_trust_tunnel_cloudflared_virtual_network" "default_cloudflared_vnet" {
  account_id = var.cloudflare_account_id
  filter = {
    is_default = true
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_virtual_networks" "default_cloudflared_vnet" {
  account_id = var.cloudflare_account_id
  is_default = true
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "rdp" {
  account_id    = var.cloudflare_account_id
  name          = "${local.environment}-tunnel"
  config_src    = "cloudflare"
  tunnel_secret = random_id.cf_tunnel_secret.hex
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "rdp_token" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.rdp.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_route" "rdp_vm_route" {
  account_id         = var.cloudflare_account_id
  tunnel_id          = cloudflare_zero_trust_tunnel_cloudflared.rdp.id
  virtual_network_id = data.cloudflare_zero_trust_tunnel_cloudflared_virtual_network.default_cloudflared_vnet.id
  network            = local.windows_vm.subnet_address_prefix
  comment            = "Route for demo RDP VM"
}

resource "cloudflare_zero_trust_access_infrastructure_target" "rdp_target" {
  account_id = var.cloudflare_account_id
  hostname   = "${local.environment}-target"

  ip = {
    ipv4 = {
      ip_addr            = module.cf_rdp_vm.virtual_machine_azurerm.private_ip_address
      virtual_network_id = data.cloudflare_zero_trust_tunnel_cloudflared_virtual_networks.default_cloudflared_vnet.result[0].id
    }
  }

  depends_on = [module.cf_rdp_vm]
}

data "cloudflare_zone" "current_zone" {
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "rdp_fqdn" {
  zone_id = var.cloudflare_zone_id
  name    = local.environment
  type    = "A"
  content = "240.0.0.0" # Placeholder IP - Cloudflare proxy handles routing
  proxied = true
  ttl     = 1

  comment = "DNS record for RDP demo - routing handled by Cloudflare proxy"
}

# Copy the helper PowerShell script to the VM and execute it
module "install_cloudflared" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm//modules/run-command"
  version = "0.19.3"

  name                       = "${local.environment}-install-cloudflared"
  location                   = local.location
  virtualmachine_resource_id = module.cf_rdp_vm.resource_id

  script_source = {
    script = file("install_cloudflared.ps1")
  }

  parameters = {
    token = {
      name  = "TunnelToken"
      value = data.cloudflare_zero_trust_tunnel_cloudflared_token.rdp_token.token
    }
  }

  tags = local.tags

  depends_on = [
    module.cf_rdp_vm,
    cloudflare_zero_trust_tunnel_cloudflared_route.rdp_vm_route
  ]
}

resource "cloudflare_zero_trust_access_policy" "allow_email" {
  account_id       = var.cloudflare_account_id
  name             = "allow-rdp-access"
  decision         = "allow"
  session_duration = "24h"

  include = [{
    email = {
      email = var.access_allowed_email
    }
  }]
}

resource "cloudflare_zero_trust_access_application" "rdp_demo" {
  account_id = var.cloudflare_account_id
  name       = "${local.environment}-rdp-access"
  type       = "rdp"
  domain     = "${local.environment}.${data.cloudflare_zone.current_zone.name}"

  destinations = [{
    type = "public"
    uri  = "${local.environment}.${data.cloudflare_zone.current_zone.name}"
  }]

  target_criteria = [{
    port     = 3389
    protocol = "RDP"
    target_attributes = {
      hostname = ["${local.environment}-target"]
    }
  }]

  app_launcher_visible        = true
  auto_redirect_to_identity   = true
  skip_interstitial           = true
  session_duration            = var.cloudflare_access_session_duration
  allow_authenticate_via_warp = false
  enable_binding_cookie       = false
  http_only_cookie_attribute  = false
  options_preflight_bypass    = false

  allowed_idps = [var.cloudflare_identity_provider_id]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow_email.id
    precedence = 1
  }]

  depends_on = [
    cloudflare_zero_trust_access_infrastructure_target.rdp_target,
    cloudflare_dns_record.rdp_fqdn
  ]
}