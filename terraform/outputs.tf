# Outputs. Values consumed by the Ansible inventory.

output "control_node_ip" {
  description = "IP address of the control-node VM."
  value       = "192.168.50.10"
}

output "control_node_vm_id" {
  description = "Proxmox VM ID of the control-node."
  value       = proxmox_virtual_environment_vm.control_node.vm_id
}