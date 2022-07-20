#cloud-config
autoinstall:
  version: 1
  locale: en_US
  keyboard:
    layout: fr
  ssh:
    install-server: true
    allow-pw: true
    disable_root: true
    ssh_quiet_keygen: true
    allow_public_ssh_keys: true
  packages:
    - qemu-guest-agent
    - sudo
  storage:
    layout:
      name: direct
    swap:
      size: 0
  user-data:
    package_upgrade: false
    timezone: Europe/Berlin
    users:
      - name: syneki
        groups: [adm, sudo]
        lock-passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        passwd: syneki
        ssh_authorized_keys:
          %{ for ssh_key in ssh_keys ~}
          - ${ssh_key}
          %{ endfor ~}