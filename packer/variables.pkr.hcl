variable "proxmox_url" {
    type = string
    default = "https://100.94.227.10:8006/api2/json"
}

variable "proxmox_api_token_id" {
    type = string
    sensitive = true
}

variable "proxmox_api_token_secret" {
    type = string
    sensitive = true
}

variable "proxmox_node" {
    type = string
    default = "pve"
}