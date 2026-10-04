# MenuTint

macOS menü çubuğundaki **beyaz** simgeleri ve yazıları (saat, Wi‑Fi, pil, uygulama menüleri, üçüncü parti simgeler…) istediğin renge boyayan küçük bir menü çubuğu uygulaması.

- Menü içinde **84 renklik palet** (tıkladığın an uygulanır, menü açık kalır)
- **Renk kodu girme** (`#FF8800`, `FF8800`, `#F80`): yazarken canlı önizleme
- **Gelişmiş Renk Seçici** (macOS renk tekerleği, kaydırıcılar, damlalık)
- **Son Kullanılanlar** satırı ve **Gökkuşağı** modu
- **Yoğunluk**: rengin ne kadar güçlü uygulanacağı
- **Hassasiyet**: yükseldikçe sönük/gri öğeler de boyanır
- Birden fazla ekran desteği, girişte otomatik başlatma
- Tıklamalar etkilenmez, menüler normal çalışır

## Nasıl çalışır?

macOS, başka uygulamaların menü çubuğu simgelerinin rengini değiştirmek için genel bir API sunmuyor. MenuTint bu yüzden:

1. **ScreenCaptureKit** ile yalnızca menü çubuğunun kendi pencerelerini (durum simgeleri, uygulama menüleri) yakalar. Duvar kağıdı ve diğer uygulamalar yakalanmaz, dolayısıyla boyanmaz,
2. Beyaz/gri pikselleri doğrudan seçtiğin renge çevirir (Core Image, GPU),
3. Sonucu menü çubuğunun hemen üstündeki şeffaf, tıklamaları geçiren bir pencerede gösterir.

Arka plan, duvar kağıdı ve zaten renkli olan simgeler (ör. yeşil pil) olduğu gibi kalır.

## Gereksinimler

- macOS 13 Ventura veya üstü
- Derlemek için Xcode ya da Xcode Command Line Tools (`xcode-select --install`)

## Kurulum

```bash
git clone https://github.com/akwnnwastaken/menutint.git
cd menutint
./scripts/build-app.sh          # Apple Silicon + Intel (tam Xcode gerekir)
# ./scripts/build-app.sh --native   # sadece bu Mac'in mimarisi (Command Line Tools yeterli)
mv build/MenuTint.app /Applications/
open /Applications/MenuTint.app
```

Hazır derlenmiş sürüm: GitHub'daki **Actions → Build** çalışmasının sonundaki `MenuTint` dosyasını indir. Uygulama imzasız olduğu için ilk açılışta Gatekeeper uyarı verir. Bu durumda uygulamaya sağ tıklayıp **Aç**'ı seç ya da şunu çalıştır:

```bash
xattr -dr com.apple.quarantine /Applications/MenuTint.app
```

### Ekran Kaydı izni

Menü çubuğunu görebilmek için uygulamanın **Ekran Kaydı** iznine ihtiyacı var:

1. İlk açılışta çıkan izin penceresinde **Sistem Ayarları**'nı aç
   (ya da MenuTint menüsünden **Ekran Kaydı İzni Ver…**),
2. *Gizlilik ve Güvenlik → Ekran ve Sistem Sesi Kaydı* altında **MenuTint**'i aç,
3. MenuTint menüsünden **MenuTint'i Yeniden Başlat**'a tıkla.

Görüntüler hiçbir yere kaydedilmez veya gönderilmez. Sadece anlık olarak boyanıp ekranda gösterilir.

## Kullanım

Menü çubuğundaki palet simgesine tıkla:

| Öğe | Ne yapar |
| --- | --- |
| Renklendirme Açık | Boyamayı açar/kapatır |
| Renk Paleti | 84 renkten birine tıkla; menü açık kalır, renkleri hızlıca deneyebilirsin |
| Son Kullanılanlar | Kod ile girdiğin veya gelişmiş seçiciden aldığın renkler |
| Gökkuşağı | Menü çubuğu boyunca renk geçişi |
| Renk Kodu Gir… | Hex kod yaz (`#FF8800`, `FF8800`, `#F80`). Yazarken önizlenir, Vazgeç eski renge döner |
| Gelişmiş Renk Seçici… | macOS renk paneli: tekerlek, RGB/HSB kaydırıcıları, ekrandan renk alma |
| Yoğunluk | %0 = orijinal beyaz, %100 = tam renk |
| Hassasiyet | Gri/sönük öğelerin de boyanması için artır; kenarlar fazla kalın görünüyorsa azalt |
| Girişte Başlat | Mac açılınca otomatik başlar (uygulama `/Applications` içinde olmalı) |

## Bilinen sınırlamalar

- **Koyu menü çubuğu için tasarlandı** (beyaz simgeler). Açık modda simgeler zaten siyah olduğu için pek bir şey değişmez.
- Menü çubuğu **otomatik gizleniyorsa** veya o ekranda menü çubuğu yoksa o ekran atlanır.
- Yakalama yapıldığı için macOS menü çubuğunda mor bir **ekran kaydı göstergesi** gösterebilir. macOS 15 ve sonrasında da arada bir izni yeniden onaylamanı isteyebilir.
- Bir simge değiştiği anda (ör. saat dakikası) boyalı katman bir kare (~16 ms) geriden gelebilir.
- Uygulamayı her yeniden derlediğinde imza değiştiği için Ekran Kaydı iznini kapatıp tekrar açman gerekebilir.

## Proje yapısı

```
Sources/MenuTint/
  AppDelegate.swift      menü çubuğu simgesi ve ayar menüsü
  TintController.swift   ekranları yönetir, yeniden başlatma, izin durumu
  MenuBarTinter.swift    bir ekran için yakalama akışı + kaplama penceresi
  FrameProcessor.swift   ScreenCaptureKit karelerini alır
  TintRenderer.swift     Core Image ile boyama
  MaskLUT.swift          hangi piksellerin "beyaz" sayılacağını belirleyen 3B renk tablosu
  Settings.swift         kalıcı ayarlar
  SliderMenuView.swift   menü içi kaydırıcı
  ColorGridView.swift    menü içi renk paleti
  HexEntry.swift         renk kodu giriş penceresi
```
