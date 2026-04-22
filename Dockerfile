# syntax=docker/dockerfile:1.7
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
ENV PUB_CACHE=/root/.pub-cache

COPY pubspec.yaml pubspec.lock ./
RUN --mount=type=cache,target=/root/.pub-cache \
    --mount=type=cache,target=/app/.dart_tool \
    flutter pub get

COPY . .

RUN --mount=type=cache,target=/root/.pub-cache \
    --mount=type=cache,target=/app/.dart_tool \
    flutter config --enable-web && flutter build web --release

FROM nginx:1.27-alpine AS runtime

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
