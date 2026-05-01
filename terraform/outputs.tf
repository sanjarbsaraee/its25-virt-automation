# Outputs. Values consumed by the Ansible inventory.

# IP read from the resource itself, not hard-coded. Workspace
# changes pick up automatically. Hard-coding would lie about
# dev workspaces, where the IP differs from main.
output "control_node_ip" {
  description = "IP address of the control-node VM."
  value       = proxmox_virtual_environment_vm.control_node.initialization[0].ip_config[0].ipv4[0].address
}

output "control_node_vm_id" {
  description = "Proxmox VM ID of the control-node."
  value       = proxmox_virtual_environment_vm.control_node.vm_id
}

output "web_01_ip" {
  description = "IP address of the web-01 VM."
  value       = proxmox_virtual_environment_vm.web_01.initialization[0].ip_config[0].ipv4[0].address
}

output "web_01_vm_id" {
  description = "Proxmox VM ID of the web-01."
  value       = proxmox_virtual_environment_vm.web_01.vm_id
}

output "db_01_ip" {
  description = "IP address of the db-01 VM."
  value       = proxmox_virtual_environment_vm.db_01.initialization[0].ip_config[0].ipv4[0].address
}

output "db_01_vm_id" {
  description = "Proxmox VM ID of the db-01."
  value       = proxmox_virtual_environment_vm.db_01.vm_id
}