FROM nginxinc/nginx-unprivileged:alpine

COPY apps/vendor-portal/index.html /usr/share/nginx/html/index.html
COPY apps/vendor-portal/app.js /usr/share/nginx/html/app.js

COPY shared/styles.css /usr/share/nginx/html/assets/styles.css

COPY apps/vendor-portal/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080