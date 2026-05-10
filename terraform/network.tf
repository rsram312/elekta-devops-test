# ----------------------------------------------------------------------------
# Virtual Network and subnet
# ----------------------------------------------------------------------------

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-elekta-devops-test"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = local.tags
}

resource "azurerm_subnet" "vms" {
  name                 = "snet-vms"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.subnet_address_prefixes
}

# ----------------------------------------------------------------------------
# Network Security Group - RDP rules
# ----------------------------------------------------------------------------

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-vms"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow RDP from a specific public IP (admin's machine)
  security_rule {
    name                       = "Allow-RDP-From-Admin-IP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.admin_source_ip
    destination_address_prefix = "*"
    description                = "Allow RDP from approved admin public IP"
  }

  # Allow RDP between VMs in the same subnet (vm-test-1 <-> vm-test-2)
  security_rule {
    name                       = "Allow-RDP-Intra-Subnet"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.subnet_address_prefixes[0]
    destination_address_prefix = "*"
    description                = "Allow RDP between VMs in this subnet"
  }

  tags = local.tags
}

# Associate the NSG with the subnet
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.vms.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ----------------------------------------------------------------------------
# Public IPs - one per VM
# ----------------------------------------------------------------------------

resource "azurerm_public_ip" "vm1" {
  name                = "pip-vm-test-1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}

resource "azurerm_public_ip" "vm2" {
  name                = "pip-vm-test-2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}