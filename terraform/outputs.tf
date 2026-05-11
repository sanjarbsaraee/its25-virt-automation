# Dynamic Fleet Status: Automatically includes every VM defined in the project.
output "vm_fleet_status" {
  description = "A dynamic summary of all deployed VMs, their roles, IPs, and Proxmox IDs."
  value = {
    for k, v in proxmox_virtual_environment_vm.nodes : k => {
      name       = v.name
      role       = local.vm_fleet[k].role
      ip_address = split("/", v.initialization[0].ip_config[0].ipv4[0].address)[0]
      vm_id      = v.vm_id
    }
  }
}