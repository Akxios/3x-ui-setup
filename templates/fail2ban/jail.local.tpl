# Managed by vps-server

[DEFAULT]
bantime  = {{FAIL2BAN_BANTIME}}
findtime = {{FAIL2BAN_FINDTIME}}
maxretry = {{FAIL2BAN_MAXRETRY}}
banaction = {{FAIL2BAN_BANACTION}}
ignoreip = {{FAIL2BAN_IGNORE_IPS}}

[sshd]
enabled = true
port = {{SSH_PORTS}}
backend = systemd

[nginx-botsearch]
enabled = {{ENABLE_NGINX_BOTSEARCH}}
