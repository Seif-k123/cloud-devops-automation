[app_servers]
%{ for ip in app_ips ~}
${ip}
%{ endfor ~}

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${key_path}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -i ${key_path} -W %h:%p -q ubuntu@${bastion_ip}"'
