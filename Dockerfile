FROM nginx:1.27-alpine AS runtime

ARG WEB_BUILD_DIR=build/web
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY ${WEB_BUILD_DIR} /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
