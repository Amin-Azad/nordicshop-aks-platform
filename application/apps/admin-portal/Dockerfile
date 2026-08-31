FROM nginxinc/nginx-unprivileged:alpine

COPY apps/admin-portal/index.html /usr/share/nginx/html/index.html
COPY apps/admin-portal/app.js /usr/share/nginx/html/app.js

COPY shared/styles.css /usr/share/nginx/html/assets/styles.css
COPY apps/admin-portal/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080
