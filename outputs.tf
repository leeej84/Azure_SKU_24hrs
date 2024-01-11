output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vm_name" {
  value = azurerm_windows_virtual_machine.main.name
}

output "public_ip_address" {
  value = azurerm_windows_virtual_machine.main.public_ip_address
}

output "admin_username" {
  value = azurerm_windows_virtual_machine.main.admin_username
}

output "admin_password" {
  sensitive = true
  value = azurerm_windows_virtual_machine.main.admin_password
}

output "region" {
  value = azurerm_resource_group.rg.location
}

output "vmsku" {
  value = azurerm_windows_virtual_machine.main.size
}