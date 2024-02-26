terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "devops-rg" {
  name     = "devops-resources"
  location = "West US 2"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "devops-vnet" {
  name                = "devops-network"
  resource_group_name = azurerm_resource_group.devops-rg.name
  location            = azurerm_resource_group.devops-rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "devops-subnet" {
  name                 = "devops-subnet"
  resource_group_name  = azurerm_resource_group.devops-rg.name
  virtual_network_name = azurerm_virtual_network.devops-vnet.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "devops-sg" {
  name                = "devops-sg"
  location            = azurerm_resource_group.devops-rg.location
  resource_group_name = azurerm_resource_group.devops-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "devops-dev-sr" {
  name                        = "devops-dev-sr"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.devops-rg.name
  network_security_group_name = azurerm_network_security_group.devops-sg.name
}

resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "allow-ssh"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.devops-rg.name
  network_security_group_name = azurerm_network_security_group.devops-sg.name
}

resource "azurerm_subnet_network_security_group_association" "devops-sg-association" {
  subnet_id                 = azurerm_subnet.devops-subnet.id
  network_security_group_id = azurerm_network_security_group.devops-sg.id
}

resource "azurerm_public_ip" "devops-pub-ip" {
  name                = "devops-pub-ip"
  location            = azurerm_resource_group.devops-rg.location
  resource_group_name = azurerm_resource_group.devops-rg.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "devops-nic" {
  name                = "devops-nic"
  location            = azurerm_resource_group.devops-rg.location
  resource_group_name = azurerm_resource_group.devops-rg.name

  ip_configuration {
    name                          = "devops-nic-ip"
    subnet_id                     = azurerm_subnet.devops-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.devops-pub-ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "devops-vm" {
  name                  = "devops-vm"
  location              = azurerm_resource_group.devops-rg.location
  resource_group_name   = azurerm_resource_group.devops-rg.name
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.devops-nic.id]

  custom_data = filebase64("customdata.tpl")

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/devopsterraazurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/devopsterraazurekey"
    })
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }

}

data "azurerm_public_ip" "devops-ip-data" {
  name                = azurerm_public_ip.devops-pub-ip.name
  resource_group_name = azurerm_resource_group.devops-rg.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.devops-vm.name}: ${data.azurerm_public_ip.devops-ip-data.ip_address}"
}