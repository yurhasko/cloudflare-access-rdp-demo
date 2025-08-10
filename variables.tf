# Azure variables
variable "azure_subscription_id" {
  description = "The Azure subscription ID"
  type        = string
}

variable "windows_vm_size" {
  description = "The size of the Windows VM"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "windows_vm_disk" {
  description = "The disk configuration for the Windows VM"
  type = object({
    caching              = string
    storage_account_type = string
    disk_size_gb         = number
  })
  default = {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }
}

variable "windows_vm_image" {
  description = "The image reference for the Windows VM"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

variable "windows_admin_username" {
  description = "The username for the Windows VM administrator"
  type        = string
  default     = "azureuser"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "The Zone ID of your Cloudflare zone where NS records will be created"
  type        = string
}

variable "cloudflare_account_id" {
  description = "The Account ID of your Cloudflare account"
  type        = string
}

variable "access_allowed_email" {
  description = "The email address of the user who is allowed to access the RDP VM"
  type        = string
}

variable "cloudflare_identity_provider_id" {
  description = "The ID of the identity provider to use for the RDP VM"
  type        = string
}

variable "cloudflare_access_session_duration" {
  description = "The duration of the Cloudflare Access session"
  type        = string
  default     = "2h"
}