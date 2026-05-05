server {
    listen 80;
    server_name {{DOMAIN}} {{WWW_DOMAIN}};

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name {{DOMAIN}} {{WWW_DOMAIN}};

    root {{WEB_ROOT}};
    index index.html;

    ssl_certificate {{NGINX_CERT_PATH}};
    ssl_certificate_key {{NGINX_CERT_KEY_PATH}};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    server_tokens off;

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer-when-downgrade always;

    location ~* \\.(env|git|htaccess|htpasswd|ini|log|conf)$ {
        deny all;
    }

    location ~* /(wp-admin|wp-login|phpmyadmin|admin) {
        return 444;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
