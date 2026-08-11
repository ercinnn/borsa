# Borsa Takip

Hisse senedi, kripto para ve diğer piyasa sembollerini takip etmek, seçilen
tarih aralığında mum grafiği ve aylık en düşük değerleri görmek, izleme
listesindeki semboller ayın en düşük değerine ulaştığında bildirim almak
için Flutter web tabanlı bir uygulama.

Veri kaynağı olarak Yahoo Finance'in genel (resmi olmayan) API'si kullanılır.
Tarayıcıdan doğrudan bu API'ye erişim CORS kısıtları nedeniyle mümkün
olmadığından, `proxy_server` adlı küçük bir Dart sunucusu yerel bir proxy
görevi görür.

## Proje yapısı

- `proxy_server/` — Yahoo Finance ve CoinGecko'ya istek atan, izleme listesi
  ve bildirimleri diskte saklayan yerel Dart sunucusu (shelf).
- `borsa_takip/` — Flutter web uygulaması (arayüz).

## Çalıştırma

Gereksinim: [Flutter SDK](https://docs.flutter.dev/get-started/install)
(Dart SDK'yı da içerir).

İki ayrı terminalde:

```powershell
cd proxy_server
dart pub get
dart run bin/server.dart
```

```powershell
cd borsa_takip
flutter pub get
flutter run -d chrome
```

Proxy sunucusu varsayılan olarak `http://localhost:8787` adresinde çalışır;
Flutter uygulaması bu adrese istek atacak şekilde ayarlıdır
(`borsa_takip/lib/services/market_api.dart`).

## Özellikler

- Favori ve aranabilir sembollerle grafik/tablo görüntüleme
- Günlük, haftalık, aylık, 3 aylık, 12 aylık mum grafiği (ekrana otomatik sığdırılır)
- Seçilen tarih aralığında aylık en düşük değer tablosu
- İzleme listesi + günde bir kez otomatik "yeni ay içi dip" kontrolü
- Tek tıkla BIST 200 / ABD popüler 200 / CoinGecko'dan canlı ilk 300 kripto ekleme
- Sayfa başına 100 bildirim gösteren, en yeninin üstte olduğu bildirim listesi

## Notlar

- `proxy_server` sürekli açık kalmadığı sürece günlük otomatik kontrol
  çalışmaz; "Bildirimler" sekmesindeki "Şimdi Kontrol Et" butonuyla manuel
  tetikleyebilirsiniz.
- BIST 200 ve ABD popüler 200 listeleri küratörlü/statik listelerdir (Yahoo
  Finance'in canlı "en çok işlem gören" verisi ek kimlik doğrulama
  gerektirdiğinden kullanılamamıştır); kripto listesi CoinGecko'dan piyasa
  değerine göre canlı çekilir.
