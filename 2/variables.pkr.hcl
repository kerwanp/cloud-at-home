variable "proxmox" {
    type = object({
        api_url = string
        token_id = string
        token_secret = string
    })
}

variable "node" {
    type = string
}

variable "ssh_keys" {
    type = list(string)
}