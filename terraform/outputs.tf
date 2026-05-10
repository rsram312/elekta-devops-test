output "resource_group_name" {
  description = "Name of the resource group containing all infrastructure."
  value       = azurerm_resource_group.rg.name
}

output "virtual_machine_names" {
  description = "Names of the deployed virtual machines."
  value = [
    azurerm_windows_virtual_machine.vm1.name,
    azurerm_windows_virtual_machine.vm2.name,
  ]
}

output "public_ip_addresses" {
  description = "Public IP addresses of the virtual machines, keyed by VM name."
  value = {
    (azurerm_windows_virtual_machine.vm1.name) = azurerm_public_ip.vm1.ip_address
    (azurerm_windows_virtual_machine.vm2.name) = azurerm_public_ip.vm2.ip_address
  }
}

output "private_ip_addresses" {
  description = "Private IP addresses of the virtual machines, keyed by VM name."
  value = {
    (azurerm_windows_virtual_machine.vm1.name) = azurerm_network_interface.vm1.private_ip_address
    (azurerm_windows_virtual_machine.vm2.name) = azurerm_network_interface.vm2.private_ip_address
  }
}
