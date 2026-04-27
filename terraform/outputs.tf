# Output values. Exposes computed values for other tools — the
# Ansible inventory in iteration 2 reads control_node_ip to know
# which host to connect to.

output "control_node_ip" {
  description = "IP address of the control-node VM."
  value       = "192.168.50.10"
}

output "control_node_vm_id" {
  description = "Proxmox VM ID of the control-node."
  value       = proxmox_virtual_environment_vm.control_node.vm_id
}