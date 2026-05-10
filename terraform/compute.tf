# ----------------------------------------------------------------------------
# Network Interfaces - one per VM
# ----------------------------------------------------------------------------

resource "azurerm_network_interface" "vm1" {
  name                = "nic-vm-test-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vms.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm1.id
  }

  tags = local.tags
}

resource "azurerm_network_interface" "vm2" {
  name                = "nic-vm-test-2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vms.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm2.id
  }

  tags = local.tags
}

# ----------------------------------------------------------------------------
# Windows Server 2022 VMs
# ----------------------------------------------------------------------------

resource "azurerm_windows_virtual_machine" "vm1" {
  name                = "vm-test-1"
  computer_name       = "vmtest1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.vm1.id,
  ]

  os_disk {
    name                 = "osdisk-vm-test-1"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  tags = local.tags
}

resource "azurerm_windows_virtual_machine" "vm2" {
  name                = "vm-test-2"
  computer_name       = "vmtest2"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.vm2.id,
  ]

  os_disk {
    name                 = "osdisk-vm-test-2"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  tags = local.tags
}