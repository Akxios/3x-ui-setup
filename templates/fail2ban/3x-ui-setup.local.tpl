# Managed by 3x-ui-setup

[sshd]
enabled = true
port = {{SSH_PORTS}}
backend = systemd
bantime = {{FAIL2BAN_BANTIME}}
findtime = {{FAIL2BAN_FINDTIME}}
maxretry = {{FAIL2BAN_MAXRETRY}}
banaction = {{FAIL2BAN_BANACTION}}
ignoreip = {{FAIL2BAN_IGNORE_IPS}}

[nginx-botsearch]
enabled = {{ENABLE_NGINX_BOTSEARCH}}
bantime = {{FAIL2BAN_BANTIME}}
findtime = {{FAIL2BAN_FINDTIME}}
maxretry = {{FAIL2BAN_MAXRETRY}}
banaction = {{FAIL2BAN_BANACTION}}
ignoreip = {{FAIL2BAN_IGNORE_IPS}}
