server {
    listen 80;
    server_name {{DOMAIN}} {{WWW_DOMAIN}};

    root {{WEB_ROOT}};
    index index.html;

    server_tokens off;

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer-when-downgrade always;

    location ~* \.(env|git|htaccess|htpasswd|ini|log|conf)$ {
        deny all;
    }

    location ~* /(wp-admin|wp-login|phpmyadmin|admin) {
        return 444;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
