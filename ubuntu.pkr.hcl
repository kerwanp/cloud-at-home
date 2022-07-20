# Génération d'une clé privée et publique d'installation
data "sshkey" "install" {}

locals {
    # Contenu qui sera servi par le serveur HTTP de Packer
    # Les fichiers meta-data et user-data sont utilisés lors de l'installation de l'OS
    data_source_content = {
        "/meta-data" = file("${path.cwd}/http/meta-data")
        "/user-data" = templatefile("${path.cwd}/http/user-data.pkrtpl.hcl", {
            # Contient les clés SSH utilisateur ainsi que celle générée automatiquement
            ssh_keys = concat([data.sshkey.install.public_key], var.ssh_keys)
        })
    }
}

source "proxmox" "ubuntu" {
 
    # L'url de l'API Proxmox
    proxmox_url = var.proxmox.api_url

    # Le nom d'utilisateur tu Token Proxmox
    username = var.proxmox.token_id

    # Le token Proxmox
    token = var.proxmox.token_secret

    # Proxmox génère son propre certificat SSL, sa source n'est donc pas reconnue
    insecure_skip_tls_verify = true
    
    # Noeud sur lequel la VM permettant de construire le template sera executée
    node = var.node

    # ID du template de VM créé
    vm_id = "901"

    # Nom du template de VM créé
    vm_name = "ubuntu"

    # Description du template de VM
    template_description = "Ubuntu"

    # Lien vers l'image ISO utilisée pour la base de notre template de VM
    iso_url = "https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso"

    # Checksum de l'image ISO, assure que le téléchargement n'est pas corrompu
    iso_checksum = "84aeaf7823c8c61baa0ae862d0a06b03409394800000b3235854a6b38eb4856f"

    # Stockage de l'image ISO
    iso_storage_pool = "local"

    # Unmount l'ISO automatiquement après l'installation
    unmount_iso = true

    # Activation de l'agent permettant à l'hôte de communiquer avec la machine virtuelle
    qemu_agent = true

    # Type de controller SCSI
    scsi_controller = "virtio-scsi-pci"

    # Montage d'un disque virtuel de 20GO
    disks {
        disk_size = "20G"
        storage_pool = "local-lvm"
        storage_pool_type = "lvm"
        type = "virtio"
    }

    # Nombre de coeurs alloués
    cores = "4"
    
    # Montant de mémoire allouée
    memory = "4096"

    # Configuration de l'adaptateur réseau en mode bridge
    # Permettant à la VM d'être considérée comme étant sur le même réseau local
    network_adapters {
        model = "virtio"
        bridge = "vmbr0"
        firewall = "false"
    } 

    # Activation de CloudInit
    cloud_init = true

    # Stockage du volume CloudInit
    cloud_init_storage_pool = "local-lvm"

    # Liste des inputs effectués une fois la VM lancée
    # L'input suivant permet de lancer l'installation de l'OS en autoinstall tout en chargeant une configuration CloudInit
    boot_command = [
        "c<wait>",
        "linux /casper/vmlinuz --- autoinstall ds=\"nocloud-net;seedfrom=http://{{.HTTPIP}}:{{.HTTPPort}}/\"",
        "<enter><wait><wait>",
        "initrd /casper/initrd",
        "<enter><wait><wait>",
        "boot",
        "<enter>"
    ]

    # Délai avant le lancement de la boot_command
    boot_wait = "5s"

    # Packer met à disposition automatiquement un serveur HTTP avec dans notre cas les fichiers user-data et meta-data (CloudInit configuration)
    http_content = local.data_source_content
    http_bind_address = "0.0.0.0"

    # Packer doit vérifier que tout s'est bien passé, pour cela il s'autentifie à la VM en SSH
    ssh_username = "syneki"
    ssh_private_key_file = data.sshkey.install.private_key_path
    ssh_pty = true
    ssh_timeout = "20m"
}

# Le build correspond à l'étape une fois que l'installation de l'OS a été effectué
build {
    # Nom du build
    name = "ubuntu"

    # Sources utilisés
    sources = ["source.proxmox.ubuntu"]

    # Cleanup de la VM et synchronisation de la configuration CloudInit
    provisioner "shell" {
        execute_command = "echo 'syneki'|{{.Vars}} sudo -S -E bash '{{.Path}}'"
        inline = [
            "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
            "sudo rm /etc/ssh/ssh_host_*",
            "sudo truncate -s 0 /etc/machine-id",
            "sudo apt -y autoremove --purge",
            "sudo apt -y clean",
            "sudo apt -y autoclean",
            "sudo cloud-init clean",
            "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
            "sudo sync"
        ]
    }

    # Fichier de configuration Cloud copié depuis la machine lançant Packer vers la VM
    provisioner "file" {
        source = "${path.cwd}/files/99-pve.cfg"
        destination = "/tmp/99-pve.cfg"
    }

    # Copie du fichier de configuration Cloud recommandé par Proxmox permettant d'optimiser le temps d'initialization de la VM.
    provisioner "shell" {
        inline = [ "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg" ]
    }
}