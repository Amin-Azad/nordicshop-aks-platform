FROM nginxinc/nginx-unprivileged:alpine

COPY apps/customer-web/index.html /usr/share/nginx/html/index.html
COPY apps/customer-web/app.js /usr/share/nginx/html/app.js

COPY shared/styles.css /usr/share/nginx/html/assets/styles.css
COPY shared/nordicshop-collection.webp /usr/share/nginx/html/assets/nordicshop-collection.webp

COPY apps/customer-web/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080