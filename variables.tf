variable "resource_group_location" {
  default     = "uksouth"
  description = "Location of the resource group."
}

variable "prefix" {
  type        = string
  default     = "tst"
  description = "Prefix of the resource name"
}

variable "ext_ip" {
  type        = string
  default     = "154.61.57.200"
  description = "External IP to allow traffic from"
}

#Standard_D2ds_v5, Standard_D2ds_v5, Standard_D2ds_v5 , Standard_D2ds_v5, Standard_D2ds_v5, 
variable "vmSize" {
  type        = string
  default     = "Standard_D2ds_v5"
  description = "VM SKU size in Azure"
}
