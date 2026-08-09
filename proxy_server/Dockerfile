# Yahoo Finance CORS proxy - AOT derlenmiş, minimal Dart imajı.
# Render.com (veya benzeri) ücretsiz bir web servisinde bu Dockerfile ile
# çalıştırılmak üzere hazırlanmıştır. Sunucu $PORT ortam değişkenini okur
# (bkz. bin/server.dart), Render bunu otomatik sağlar.

FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
WORKDIR /app
EXPOSE 8787
CMD ["/app/bin/server"]
