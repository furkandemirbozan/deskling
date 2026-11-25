<div align="center">

<img src="docs/images/robot.png" width="180" alt="Deskling robotu">

# Deskling

**Masaüstünde yaşayan küçük yardımcın: ekran görüntülerini toplayan robot süpürge, altına dosya saklayabildiğin Türk motifli halı, fareyle kardan adam yapabildiğin gerçekçi kar, dosyaları sıkıştıran bir kara delik, port ve Docker kontrol merkezi, akıllı pano yöneticisi, içeceği gerçekten azalan bir Pomodoro sayacı ve MacBook çentiğinde açılan bir dinamik ada.**

macOS · Swift · AppKit · SwiftUI · Core Animation · Metal

</div>

---

Deskling bir robot süpürge olarak başladı, sonra masaüstünün her köşesine yayıldı. Her şey tek bir menü çubuğu uygulamasında, internet bağlantısı olmadan ve verilerin bu Mac'ten çıkmadan çalışır. Her özellik ayrı ayrı açılıp kapatılabilir.

### Robot süpürge

Masaüstün ekran görüntüleriyle dolduğunda robota çift tıkla. Robot istasyonundan çıkar, her ekran görüntüsüne tek tek gider, onu animasyonla içine çeker ve istasyondaki kutuya boşaltır. **Hiçbir dosya silinmez.** Toplananlar bir klasörde seni bekler, neyi saklayacağına sen karar verirsin.

| Tarıyor | Süpürüyor | Kutuya boşaltıyor |
| :---: | :---: | :---: |
| <img src="docs/images/tarama.png" alt="Robot masaüstünü tarıyor"> | <img src="docs/images/supurme.png" alt="Robot ekran görüntüsünü süpürüyor"> | <img src="docs/images/bosaltma.png" alt="Robot görüntüleri kutuya boşaltıyor"> |

## Özellikler

- **Masaüstünde yaşar:** Robot sol alt köşedeki istasyonunda durur. Masaüstü simgelerinin üstünde, açık pencerelerin arkasında kalır.
- **Çift tıkla çalışır:** Robota çift tıklaman yeterli, onay sormaz.
- **1 saat kuralı:** Masaüstünde 1 saati geçen ekran görüntülerini robot kendiliğinden toplar.
- **Mac açılınca başlar:** Uygulamalar klasöründen çalışırken oturum açıldığında kendiliğinden gelir.
- **Yalnızca gerçek ekran görüntülerini alır:** Dosya adına bakmaz, macOS'un ekran görüntüsü işaretini arar.
- **Silmez, toplar:** Görüntüler istasyondaki kutuya, yani bir klasöre taşınır.
- **Kutuya tıkla, klasörü aç:** İstasyondaki kutuya tek tıklayınca topladığı görüntüler Finder'da açılır.
- **Denetim paneli:** Bulunan görüntüleri önizle, seç, kilitle ve geçmişten geri al.
- **Canlı animasyonlar:** Dönen fırçalar, lidar, tarama dalgaları ve kutuya uçan görüntüler.
- **İçine çekerek alır:** Robot dosyanın önünde durur, dosya uzayıp küçülerek ağzından içeri girer.
- **Çarptığını iter:** Yoluna çıkan dosya ve klasörler darbeyle yana kayar. Panelden kapatılabilir.
- **Her gezinti farklı:** Temizlenecek bir şey yoksa zikzak, döngü, sekiz, spiral gibi değişen rotalarda gezer.
- **Türk motifli halı:** Masaüstünde sürükle, köşesinden katla, dosyalarını altına süpür.
- **Gerçekçi kar:** Pencerelerin üstünde ve ekranın altında birikir, pencere sallanınca veya kapanınca dökülür.
- **Kar küreme aracı:** Zemin dolunca küçük bir kamyon gelip karı temizler.
- **Kara delik:** Sol üst köşedeki kara deliğe dosya bırak: görselleri, PDF'leri ve videoları sıkıştırır, PDF birleştirir, ZIP yapar, arşiv açar, JSON ve CSV dönüştürür.
- **Portlar ve servisler:** Dinlenen portları gör, tek tıkla tarayıcıda aç ya da kapat, Docker konteynerlerini başlat ve durdur.
- **Pano yöneticisi:** ⇧⌘V ile kopyalama geçmişine ulaş, klavyeyle seç ve yapıştır.
- **İçecekli Pomodoro:** Masaüstündeki çay, Türk kahvesi, kahve ya da bira odak süresiyle birlikte azalır, molada yeniden dolar.
- **Dinamik ada:** Fare MacBook'un çentiğine gelince çalan şarkı, zamanlayıcılar ve dosya rafı açılır. Şarj, ses ve kulaklık değişince kısa bildirimler gösterir.
- **Kar topu ve kardan adam:** Biriken karı fareyle yuvarla, topları üst üste koyup süsle. Yüksekten düşen kardan adam kar yığınına döner.
- **Pil ve şarj:** Pili azalan robot görevine ara verip istasyonda şarj olur, sonra kaldığı yerden devam eder.

## Türk motifli halı

Koçboynuzu bordürü, Selçuklu yıldızları ve basamaklı göbekleriyle tamamen kodla dokunan bir halı. Altına süpürdüğün her şey masaüstünden kaybolur ve robot onlara dokunamaz.

| Örtülü | Köşesinden katlanmış |
| :---: | :---: |
| <img src="docs/images/hali.png" alt="Türk motifli halı"> | <img src="docs/images/hali-katli.png" alt="Köşesi katlanmış halı ve altındaki dosyalar"> |

| Yapmak istediğin | Nasıl? |
| --- | --- |
| Halıyı taşı | Ortasından tutup sürükle |
| Köşesini katla | Köşesini içeri doğru çek ya da köşeye tıkla |
| Altına süpür | Dosya, klasör veya ekran görüntüsünü halının üstüne bırak |
| Örtüp kapat | Katlanmış kısma tıkla |
| Geri çıkar | Katlayıp dosyayı dışarı sürükle ya da sağ tıkla → **Masaüstüne Geri Çıkar** |
| Boyutunu değiştir | Sağ tıkla → **Küçük / Orta / Büyük Halı** ya da **Ayarlar** → **Boyut** (%60–%160) |
| Gizle veya göster | Sağ tıkla → **Halıyı Gizle** ya da menü çubuğundaki simge |

Halının altına süpürülen dosyalar şu özel klasöre taşınır, robot bu klasöre hiç bakmaz:

```text
~/Library/Application Support/Deskling/Halı Altı
```

**Touch ID kilidi.** Halının altında dosya varken halıyı açmak, menüden ya da sağ tıkla Finder'da göstermek Touch ID ister; Touch ID yoksa Mac parolası sorulur. Kilitliyken de dosya süpürebilirsin, halı kalkar ama altındakiler görünmez. Halı kapandıktan 1 dakika sonra, Mac uyuyunca ya da ekran kilitlenince yeniden kilitlenir. **Ayarlar → Halı** bölümünden kapatılabilir. Kilit Deskling içindir; klasör Finder'dan elle açılırsa sorulmaz.

Halıyı bir ekran görüntüsünün üstüne çekmek de onu robottan korur. Bu koruma Finder'ın bildirdiği simge konumuna bağlıdır ve halı gizlenince kalkar. Kesin koruma için dosyayı halının altına süpür.

## Kar

Metal ile çizilen, ekrandaki gerçek pencereleri takip eden bir kar simülasyonu. Kar tıklamaları engellemez, Dock ve menü çubuğunun arkasından geçer.

<div align="center">
<img src="docs/images/kar.png" alt="Pencerelerin üstünde ve ekranın altında biriken kar">
</div>

| Olay | Kar ne yapar? |
| --- | --- |
| Yağış | Küçük taneler rüzgârla süzülür, havada değen taneler birleşip büyür |
| Birikme | Pencerelerin üst kenarında ve ekranın altında topaklı bir örtü oluşur |
| Yavaş taşıma | Kar pencerenin üstünde kalır |
| Hızlı taşıma veya sallama | Kar kopar, topak topak dökülür |
| Boyut değiştirme | Kenardan taşan kar düşer, kalanı yeni genişliğe oturur |
| Kapatma veya Dock'a indirme | Pencerenin üstündeki karın tamamı aşağı düşer |
| Sınıra ulaşma | Kar pencerede 16, zeminde 44 noktadan fazla yükselmez |

### Kar küreme aracı

<div align="center">
<img src="docs/images/kureme.png" alt="Zemindeki karı temizleyen kar küreme aracı">
</div>

Zemin, birikme sınırının yarısına kadar dolunca turuncu bir kamyon ekrana girer. Karı bıçağıyla önüne katar, havaya savurur ve diğer uçtan çıkar. Her geçişten sonra en az bir dakika bekler.

Karı ve küreme aracını menü çubuğundaki simgeden ya da **Ayarlar** sekmesinden açıp kapatabilirsin. Yoğunluk ve birikme sınırı da aynı sekmeden ayarlanır.

### Kar topu ve kardan adam

<div align="center">
<img src="docs/images/kardan-adam.png" alt="Üç kar topundan yapılmış süslü kardan adam">
</div>

| Yapmak istediğin | Nasıl? |
| --- | --- |
| Kar topu yap | Biriken karın üstüne sol tıkla, bir avuç kar alınır |
| Topu büyüt | Basılı tutup karın üstünde sürükle. Top yuvarlandıkça karı toplar, arkasında iz kalır |
| Kardan adam yap | Bir topu başka bir topun üstüne bırak. İkinci topla yüz ve kollar, üçüncüyle şapka ve atkı gelir |
| Süsle | Topa sağ tıkla: gözler, havuç burun, dal kollar, düğmeler, şapka, atkı |
| Kardan adamı taşı | En alttaki topu tut. Üstündeki toplar onunla birlikte gelir, sertçe sallarsan düşerler |
| Fırlat | Topu hızla savurarak bırak |
| Kar yığınından top yap | Yığına tıkla ya da topu yığının üstünde yuvarla |

### Yer çekimi

<div align="center">
<img src="docs/images/kar-yigini.png" alt="Yüksekten düşüp süsleriyle birlikte kar yığınına dönen kardan adam">
</div>

| Düşme | Ne olur? |
| --- | --- |
| Alçaktan | Top sağlam kalır, bir an ezilip toparlanır |
| Orta yükseklikten | Top kalıcı olarak basıklaşır, üstündeki toplar sarsılıp düşebilir |
| Yüksekten (yaklaşık ekranın yarısı) | Top dağılır. Bir kısmı topak topak sıçrar, kalanı yerde yayılan bir kar yığını olur |
| Kardan adam yüksekten | Bütün toplar tek bir yığına çöker. Şapka, havuç, kollar, atkı ve kömürler yığının üstüne düşer |
| Bir top başka bir topun üstüne hızla | İkisi birbirine gömülür ve alttaki topun yerinde tek bir yığın olur |

Yığınlar zeminin biçimini izler, çukurlara ve topun bıraktığı izlere dökülür. Yağan kar yığınlara da yapışır.

Toplar pencerelerin üstünde de durur. Pencere yavaşça taşınırsa top onunla gider, sertçe çekilir ya da kapanırsa düşer. Küreme aracı yerdeki kar yığınlarını kürer. Küçük topları bıçağının önüne katıp yuvarlar, top yolundaki karı toplayarak büyür. Büyük topları ve kardan adamları ise parçalayıp önündeki kara katar. Pencerelerin üstündeki toplara dokunmaz.

Pencere yalnızca imleç birikmiş karın veya bir topun üstündeyken tıklamayı alır, geri kalan her yerde tıklama alttaki uygulamaya geçer. Bu özelliği **Ayarlar > Fareyle kar topu yapılsın** ile kapatabilirsin.

## Kara delik

<div align="center">
<img src="docs/images/kara-delik.png" alt="Işığı büken birikim diskiyle masaüstündeki kara delik">
</div>

Masaüstünün sol üst köşesinde, ışığı büken bir birikim diskiyle dönen bir kara delik durur. Üstüne dosya sürükleyince çekim alanı büyür, disk hızlanır ve dosyaya doğru bir akıntı uzanır. Bıraktığın dosya spiral çizip diske yassılarak içeri çekilir. İşlem bitince sonuç parçacıklarla dışarı fırlar, deliğin üstünde birkaç saniye bir etiket görünür.

| Bırakış | Renk | Ne olur? |
| --- | --- | --- |
| Görsel (PNG, JPG, HEIC, TIFF, WebP) | Mor | Sıkışır ya da dönüşür (`_compressed`, HEIC ve WebP için `_converted`) |
| Tek PDF | Mor | İçindeki görseller yeniden sıkıştırılır, yazılar keskin kalır (`_compressed.pdf`) |
| Birden çok PDF | Mor | Bırakıldığı sırayla tek PDF'te birleşir (`_merged.pdf`) |
| Video (MOV, MP4, M4V) | Mor | HEVC ya da H.264 ile hafif bir MP4'e sıkışır (`_compressed.mp4`) |
| Klasör ya da karışık dosyalar | Mor | Tek bir ZIP olur |
| Tek satırlık JSON | Mor | Okunur hale gelir (`_formatted.json`) |
| Girintili JSON | Mor | Tek satıra küçülür (`_minified.json`) |
| CSV | Mor | JSON'a dönüşür (`_converted.json`) |
| ZIP, TAR, TAR.GZ ya da **Shift** basılı | Beyaz | Arşiv yanındaki klasöre açılır |
| **Shift** ile tek PDF | Beyaz | Her sayfa ayrı PDF olarak bir klasöre çıkar |
| **Shift** ile görseller | Beyaz | Görseller tek bir PDF'in sayfaları olur |
| **Shift** ile sesli video | Beyaz | Sesi M4A olarak ayrılır (`_audio.m4a`) |
| **Shift** ile sessiz kısa video | Beyaz | En fazla 30 saniyelik video, saniyede 10 karelik bir GIF olur |
| **Option** basılı | Kırmızı | Dosyalar Çöp Sepeti'ne taşınır |

Kırmızı mod dışında orijinal dosyaya hiç dokunulmaz. Çıktı orijinalin yanına kaydedilir, aynı adda bir dosya varsa üzerine yazılmaz. İşlenemeyen dosyayı kara delik geri tükürür. JSON düzenlenirken anahtar sırası korunur. CSV'de noktalı virgül, tırnaklı alanlar ve Windows Türkçe kodlaması tanınır. ZIP'ler `__MACOSX` artığı içermez, her sistemde temiz açılır.

Kara deliği sürükleyip istediğin yere taşıyabilirsin. Sağ tıklayınca kısa bir kullanım özeti, "İşlemden sonra orijinali Çöp Sepeti'ne taşı" seçeneği, yerine geri koyma ve gizleme seçenekleri açılır. Menü çubuğundaki simgeden ve **Ayarlar** sekmesinden de açılıp kapatılabilir.

Görsellerde çıktı biçimi (JPG, HEIC, WebP) ve kalite (Düşük, Orta, Yüksek) sağ tık menüsünden ya da **Ayarlar** sekmesinden seçilir. Düşük kalitede uzun kenar 2048, ortada 3840 pikselle sınırlanır, yüksekte boyut değişmez. Fotoğraflardaki konum bilgisi varsayılan olarak silinir, diğer fotoğraf bilgileri korunur. Yan çekilmiş fotoğraflar düz kaydedilir, saydam ekran görüntüleri JPG olurken beyaz zemine oturur. Sıkıştırma dosyayı küçültmezse yeni dosya tutulmaz ve kara delik dosyayı geri tükürür. Şifreli PDF'lere dokunulmaz.

WebP yazmak için `cwebp` gerekir, macOS bunu kendisi yazamaz. Kurulu değilse WebP seçeneği kapalı görünür:

```bash
brew install webp
```

Videolar da aynı kalite ayarını kullanır: düşük kalite 720p H.264, orta kalite 1080p HEVC, yüksek kalite çözünürlüğü koruyan HEVC verir. Video gibi uzun süren işlerde kara deliğin üstünde bir ilerleme yüzdesi görünür. MKV ve AVI dosyalarını macOS açamadığı için bunlar yalnızca `ffmpeg` kuruluysa işlenir:

```bash
brew install ffmpeg
```

## Portlar ve servisler

<div align="center">
<img src="docs/images/portlar.png" width="460" alt="Dinlenen portlar ve Docker konteynerleri">
</div>

Denetim panelindeki **Portlar** sekmesi, terminal açıp `lsof` yazmadan geliştirme ortamını yönetmeni sağlar. Menü çubuğundaki **Portlar ve Servisler** ile doğrudan açılır.

- O an dinlenen bütün TCP portlarını, kullanan uygulamayı, çalıştığı klasörü ve komutunu gösterir. IPv4 ve IPv6 kayıtları tek satırda birleşir.
- Her port **yalnızca bu Mac** ya da **ağa açık** diye işaretlenir.
- 🧭 ile `http://localhost:PORT` tarayıcıda açılır. ✕ ile süreç kibarca kapatılır, kapanmazsa **Zorla kapat** çıkar.
- Başka kullanıcıya ait süreçler kapatılamaz. macOS servisleri için önce onay istenir. 5000 ve 7000 portlarını tutan AirPlay Alıcısı için nasıl kapatılacağı yazılır.
- Docker konteynerleri, Compose proje adı ve yayınladığı portlarla listelenir. Tek tıkla başlatılır ya da durdurulur. Docker Desktop kapalıysa açma düğmesi çıkar.
- Sekme açıkken liste 4 saniyede bir yenilenir, kapalıyken hiç tarama yapılmaz.

## Pano yöneticisi

<div align="center">
<img src="docs/images/pano.png" width="470" alt="Pano geçmişi penceresi">
</div>

Kopyaladığın metinleri, bağlantıları, kod parçalarını ve renk kodlarını kaynak uygulamasıyla birlikte saklar. **⇧⌘V** ile hangi uygulamadaysan imlecin yanında, odağı çalmadan açılır.

| Tuş | Ne yapar? |
| --- | --- |
| ↑ ↓ | Kayıtlar arasında gezinir |
| ↩ | Seçili kaydı öndeki uygulamaya yapıştırır |
| ⇧↩ ya da ⇧ tık | Biçimi bırakıp düz metin olarak yapıştırır |
| ⌘1 – ⌘9 | İlk dokuz kayıttan birini hemen yapıştırır |
| ⌘P | Sabitler; sabitlenenler en üstte kalır ve silinmez |
| ⌘⌫ | Kaydı siler |
| ⎋ | Pencereyi kapatır |

- Arama Türkçe harflere duyarsızdır. "renk", "link" ya da "kod" yazınca o türdekiler gelir.
- Renk kodlarının yanında rengi görünür. HEX, RGB ve HSL arasında tek tıkla çevrilip kopyalanır.
- Aynı metni yeniden kopyalarsan yeni kayıt açılmaz, var olan en üste çıkar.
- Pano yalnızca değiştiğinde okunur (`changeCount`), boştayken işlemciye yük olmaz.
- Parola yöneticilerinin gizli işaretlediği kopyalar ve Finder'da kopyalanan dosyalar kaydedilmez.
- Geçmiş yalnızca bu Mac'te, yalnızca senin okuyabildiğin bir dosyada (`~/Library/Application Support/Deskling/pano.json`) tutulur.

Otomatik yapıştırma için macOS **Erişilebilirlik** izni ister. İzin yoksa seçtiğin kayıt panoya kopyalanır, ⌘V ile yapıştırırsın. Kısayolu, kayıt sınırını ve izni **Ayarlar > Pano** bölümünden değiştirebilirsin. ⇧⌘V bazı uygulamalarda "Biçimi eşleştirerek yapıştır" kısayoludur; istersen başka bir kısayol seçebilirsin.

## İçecekli Pomodoro

<div align="center">
<img src="docs/images/icecekler.png" alt="İnce belli çay, Türk kahvesi, seramik kupa ve bira bardağı">
</div>

Masaüstünde bir içecek durur ve odak süresi boyunca yavaş yavaş azalır. Hepsi kodla çizilir; dışarıdan resim ya da GIF kullanılmaz.

| İçecek | Neler var? |
| --- | --- |
| **İnce belli çay** | Tavşan kanı çay, kalın camlı dip, porselen tabak ve kaşık. Buhar süre ilerledikçe incelir, sona doğru kesilir. Süre bitince bardak titrer, kaşık tabakta şıngırdar. |
| **Türk kahvesi** | Altın yaldızlı, lale motifli fincan. Köpük hafifçe nefes alır; kahve azaldıkça fincanın çeperinde telve izi kalır. |
| **Kahve** | Mat seramik kupa, koyu kahve, yüzeyde dalgalanan pencere yansıması. Molada akan kahveyle yeniden dolar. |
| **Bira** | Kehribar bira, kabarık köpük, dipten yükselen baloncuklar, terleyen cam. Her yudum camda ince bir köpük izi bırakır. |

- **Sürükle:** Bardağı tutup taşıdığında sıvı hareketin tersine yığılır, bırakınca yavaşça durulur.
- **Üzerine gel:** Bardağın altında kalan süre, başlat/duraklat, sıfırla ve atla düğmeleri belirir.
- **Çift tıkla:** Sayacı başlatır ya da duraklatır.
- **Sağ tıkla:** İçeceği, boyutu değiştir ya da gizle.
- **Menü çubuğu:** Sayaç çalışırken içeceğin simgesi ve kalan süre (`24:12`) görünür; simge de süreyle birlikte boşalır.
- **Döngü:** 25 dakika odak, 5 dakika mola, 4 odakta bir 15 dakika uzun mola. Hepsi değiştirilebilir.
- **Uyarılar:** Süre bitince macOS bildirimi ve içeceğe yakışan yumuşak bir ses gelir; ikisi de kapatılabilir.
- **Uyanık tut:** İstersen odak sırasında ekran kararmaz.
- **Robot ve karla birlikte:** İstersen odakta kar yağışı ve robot duraklar. Molada robot, odak sırasında masaüstüne düşen ekran görüntülerini toplar. Kilitli ve halının altındaki dosyalara dokunmaz.

<div align="center">
<img src="docs/images/odak.png" width="420" alt="Denetim panelindeki Odak sekmesi">
</div>

Sayaç uygulama kapanıp açılsa da kaldığı yerden sürer. Animasyon yoğunluğu **Düşük** seçilirse kare hızı ve partikül sayısı azalır.

## Dinamik ada

<div align="center">
<img src="docs/images/ada.png" width="640" alt="Dinamik adanın kulakları, şarj bildirimi ve açık sayfaları">
</div>

MacBook'un çentiği, iPhone'daki gibi canlı bir adaya dönüşür. Ada çentikten aşağı yaylanarak büyür, iş bitince yeniden çentiğe çekilir. Çentiksiz ekranlarda menü çubuğunun ortasında da gösterilebilir.

**Kulaklarda süren etkinlikler.** Bir şey sürerken çentiğin iki yanında küçük kulaklar belirir. Aynı anda iki etkinlik varsa ikincisi yanda ayrı bir baloncukta durur.

| Etkinlik | Kulakta görünen |
| --- | --- |
| **Şu an çalan** | Albüm kapağı ve kapağın rengine bürünen ekolayzer çubukları. Müzik, Spotify ve tarayıcıda YouTube Music, YouTube, Spotify, SoundCloud, Apple Music, Deezer |
| **Pomodoro** | Süreyle boşalan içecek simgesi ve kalan süre |
| **Zamanlayıcı** | Azalan halka ve kalan süre |
| **Kronometre** | Geçen süre |
| **Robot** | Toplanacak kaç görüntü kaldığı |
| **Kara delik** | Video sıkıştırma gibi uzun işlerde dönen kara delik ve yüzde |
| **Bellek ve disk uyarısı** | Bellek baskısı artınca "RAM %94", disk azalınca kalan yer. Tıklayınca tek tıklık temizlik sunar |

**Kısa bildirimler.** Birkaç saniye görünüp kaybolur:

- Şarja takınca, çıkarınca, pil %20 ve %10'un altına inince, pil dolunca
- Ses açılıp kısılınca ince bir ses çubuğu
- AirPods, kulaklık ya da hoparlör değişince aygıtın adı ve simgesi
- Bir şey kopyalanınca "Kopyalandı"
- Robot görevi bitince "4 ekran görüntüsü kutuya alındı"
- Kara delikteki uzun iş bitince sonucu, örneğin "Video 1,2 GB → 180 MB"

**Tarayıcıdaki müzik.** YouTube Music, YouTube, Spotify, SoundCloud, Apple Music, Deezer ve Tidal sekmeleri okunur; başka sekmelere bakılmaz. Çalıp çalmadığı sistemin ses bilgisinden anlaşılır.

| Tarayıcı | Ne gelir? |
| --- | --- |
| Chrome, Brave, Edge, Vivaldi, Opera, Arc | "Apple Events'ten JavaScript'e izin ver" açıksa (menü çubuğunda Görünüm → Geliştirici) kapak, sanatçı, süre, konum ve sayfa içi denetim. Kapalıysa sekme başlığı gelir; oynat/duraklat ve ileri/geri sistemin "Şimdi Çalıyor" komutuyla yapılır, izin gerekmez. Birden çok profil varsa ayar her profilde ayrıdır. |
| Safari | Aynısı; ayar Safari Ayarları → Geliştirici bölümündedir (önce Gelişmiş'te "Web geliştiricileri için özellikleri göster" açılır). |
| Firefox, Zen | Firefox sekmeleri dışarıya açmaz; şarkı adı pencere başlığından Erişilebilirlik izniyle okunur; denetim sistemin "Şimdi Çalıyor" komutuyladır. Kapak ve süre gelmez. |

**Açık ada.** Fare çentiğe gelince ada açılır. Üst sırada sayfalar, pil, saat ve ayarlar düğmesi durur.

| Sayfa | Ne var? |
| --- | --- |
| **Şimdi** | Kapak, şarkı ve sanatçı, sürüklenebilir ilerleme çubuğu, geri/oynat/ileri, ses düzeyi. Yanda Pomodoro ve tek tıkla zamanlayıcı. Kapağa tıklayınca müzik uygulaması açılır. |
| **Zamanlayıcı** | 1–60 dakikalık hazır süreler ya da kendi süren; duraklat, +1 dk, +5 dk. Yanında turlu kronometre. Süre dolunca ada açılır, ses çalar; **+5 dk** ile ertelenebilir. |
| **Raf** | Dosyaları çentiğe sürükleyip bırak. Rafta bekler, istediğin yere sürükleyip çıkarırsın. AirDrop ile gönder, Finder'da göster. Dosyalar taşınmaz, kopyalanmaz; raf yalnızca yerlerini hatırlar. |

Pomodoro'da odak ya da mola bitince ada kısa bir uyarıyla açılır. Açılırken trackpad hafifçe titrer.

**Tam ekranda.** Tam ekran bir uygulamada masaüstündeki robot, içecek ve kara delik görünmez. Ada bu sırada bildirim merkezi gibi çalışır. Boşken görünmez ve fare menü çubuğuna gidince açılmaz. Süren etkinlikler, kısa bildirimler ve uyarılar yine çentikte belirir. Ada sekmesinden "her zamanki gibi" ya da "tamamen gizle" de seçilebilir.

**Bellek ve disk uyarıları.** Deskling yarım dakikada bir bellek baskısına ve boş disk alanına bakar. Uyarı şu durumlarda çıkar:

- macOS bellek baskısını "yüksek" bildirirse.
- Bellek neredeyse doluyken takas 6 GB'ı geçerse.
- Diskte 15 GB'tan ya da %5'ten az yer kalırsa.

Uyarı çıkınca kulakta küçük bir gösterge belirir. Göstergeye tıklayınca uyarı açılır. Bellek uyarısında kapatılabilecek uygulamaların adı ve ne kadar yer açılacağı yazar; **Belleği temizle** düğmesi bu uygulamaları nazikçe kapatır. Disk uyarısındaki **Diski incele** düğmesi Disk sekmesini açar ve taramayı başlatır. **Sonra** düğmesi uyarıyı bir saat susturur. Durum kritikleşirse, yani bellek baskısı "kritik" olursa ya da diskte 5 GB'tan az yer kalırsa, ada saatte en fazla bir kez kendiliğinden açılır.

Panelin **Ada** sekmesinden adanın tamamı ya da her etkinlik tek tek kapatılabilir. Açılma gecikmesi, ikinci etkinlik baloncuğu, dokunsal geri bildirim, tam ekranda gizlenme ve zamanlayıcı sesi de buradan ayarlanır. Zamanlayıcı menü çubuğundaki simgeden de başlatılabilir.

## Disk ve bellek

Panelin **Disk** sekmesi diskte neyin yer kapladığını bölüm bölüm gösterir ve neyin silinebileceğini söyler. Tarama yalnızca **Diski tara** düğmesine basınca yapılır ve hiçbir şeyi değiştirmez.

**Grafik.** Üstte diskin tamamı tek çubukta: her bölüm kendi renginde, yanında "Sistem ve diğer" ve boş alan. Altında halka grafik; bir dilime ya da yanındaki satıra tıklayınca o bölüm açılır. Bölümün içi de parça parça bir çubuğa bölünür. Her parça kapladığı yer kadar geniştir, rengi kararı gösterir: kırmızı silinebilir, turuncu gözden geçir, yeşil gerekli. Parçaya tıklayınca listede o öğeye gidilir. Sağ tıkla Finder'da gösterilir ya da Çöp Kutusu'na taşınır.

| Bölüm | Neye bakılır? |
| --- | --- |
| Uygulamalar | Son açılma tarihi, kaç kez açıldığı, ne zamandır yüklü olduğu, şu an açık olup olmadığı |
| Önbellekler | Son değişiklik, sahibi olan uygulamanın açık olup olmadığı; silinse de yeniden oluşur |
| Günlükler | Ne kadar eski olduğu |
| Geliştirici | Xcode DerivedData, simülatör önbellekleri, cihaz destek dosyaları; npm, NuGet, pnpm, Yarn ve Gradle önbellekleri; projelerdeki .NET bin/obj ve node_modules klasörleri; Docker artıkları |
| İndirilenler | Kurulum dosyaları (.dmg, .pkg, .zip…) ve ne zamandır açılmadığı |
| Büyük dosyalar | Belgeler, Masaüstü, Filmler, Müzik ve Resimler'deki 500 MB'tan büyük dosyalar |
| iPhone yedekleri | Yedeğin tarihi; en yenisi her zaman korunur |
| Çöp Kutusu | Yalnızca boyutu gösterilir |

**Kararlar.**

- **Gerekli** olanlar silinmeye önerilmez, seçilemez ve Çöp Kutusu'na taşınamaz:
  - Son 30 günde kullanılmış uygulamalar.
  - Şu an açık uygulamalar.
  - 60 günden yeni yüklenmiş uygulamalar.
  - Apple uygulamaları.
  - Deskling'in kendisi ve halının altındakiler.
  - Kilitli dosyalar.
  - Fotoğraflar ve Müzik arşivleri.
  - En yeni iPhone yedeği.
  - Son 30 günde açılmış indirmeler.
  - Son 90 günde açılmış büyük dosyalar.
- **Silinebilir** önerileri:
  - 6 aydır açılmamış uygulamalar.
  - Yeniden oluşturulabilen eski önbellekler ve günlükler.
  - Eski derleme artıkları.
  - İşi bitmiş kurulum dosyaları.
  - Bir yıldır açılmamış indirmeler.
- **Sık kullanılmış uygulamalar** uzun süre açılmasa da en fazla "gözden geçir" olur.
- **Kişisel büyük dosyalar** hiçbir zaman "silinebilir" sayılmaz; kararı sana bırakılır.

Her satırda kararın gerekçesi yazar, örneğin "10 ay önce kullanıldı · 4 kez açıldı · 1 yıldır yüklü". **Önerilenleri seç** yalnızca silinebilirleri seçer.

**Geliştirici temizliği.** Geliştirici bölümünün başındaki **Tek tıkla temizle** düğmesi yalnızca "silinebilir" olanları temizler:

- 14 gündür derlenmemiş .NET `bin` ve `obj` klasörleri. Yalnızca yanında `.csproj` olan klasörlere bakılır.
- 60 gündür dokunulmamış projelerin `node_modules` klasörü.
- Eski DerivedData ve paket önbellekleri.
- Docker'da etiketsiz imajlar ve kullanılmayan derleme önbelleği.

Docker'daki şu artıklar "gözden geçir" olarak listelenir ve tek tıkla temizliğe girmez; tek tek silinebilirler:

- Kullanılmayan imajlar.
- Durmuş konteynerler.
- Hiçbir konteynere bağlı olmayan birimler. Bunlar veritabanı verisi içerebilir.

Klasörler Çöp Kutusu'na taşınır. Docker artıkları Çöp Kutusu'na gidemediği için `docker` komutuyla kalıcı silinir; onay penceresi bunu ayrıca söyler.

**Silme.** Silmek her zaman onay ister ve dosyaları Çöp Kutusu'na taşır; kalıcı silme yoktur, Çöp Kutusu'ndan geri alınabilir. Yer, Çöp Kutusu Finder'dan boşaltılınca açılır. Taşıma anında açık olan uygulama taşınmaz.

**Bellek.** Aynı sekmenin **Bellek** sayfasında şunlar var:

- Belleğin dağılımı: uygulamalar, kablolu, sıkıştırılmış ve önbellek.
- Bellek baskısı ve takas kullanımı.
- Açık uygulamaların yardımcı süreçleriyle birlikte kullandığı bellek.

300 MB'tan fazla kullanan ve 30 dakikadır arka planda bekleyen uygulamalar "kapatılabilir" diye işaretlenir. Bu uygulamalar **Belleği temizle** ile tek seferde kapatılır. Hiçbir zaman kapatılmaya önerilmeyenler:

- Öndeki uygulama.
- Ses çalan uygulama.
- Az önce kullanılan uygulama.
- Deskling ve Finder.

Uygulamalar nazikçe kapatılır; kaydedilmemiş belge varsa uygulama kendisi sorar. **Önbelleği boşalt**, macOS'un `purge` aracını çalıştırır. Yönetici parolasını macOS kendi penceresinde sorar ve etkisi geçicidir.

## Klavye sesleri

Deskling, mekanik klavye gibi her tuşa basışta ses çıkarabilir. Bu özellik varsayılan olarak kapalıdır; panelin **Klavye** sekmesinden ya da menü çubuğundaki **Klavye Sesi** menüsünden açılır. Aynı menüden paketler arasında geçilebilir. Paket değişince dinamik adada paketin adı kısaca görünür.

**Paketler iki yerden gelir:**

- **Dahili paketler:** Deskling · Tık, Tok, Daktilo ve Baloncuk. Bunlar dosya gerektirmez; sesler kodla üretilir. Daktiloda Enter'a basınca satır sonu zili çalar.
- **Mechvibes paketleri:** [mechvibes.com](https://mechvibes.com/sound-packs?sort=downloads) üzerinde 1.000'den fazla topluluk paketi var. İndirdiğin zip'i paket klasörüne atman yeterli. Varsayılan klasör `~/Documents/KlavyeSesDosyaları`; panelden değiştirilebilir. Disk sekmesi bu klasörü hiçbir zaman silinmeye önermez ve Çöp Kutusu'na taşımaz; klasör panelden değiştirilse de korunur. Deskling klasörü izler ve yeni zip'i birkaç saniye içinde listeye ekler.

Klasöre dokunulmaz: zip'ler olduğu gibi kalır, Deskling kendi kopyasını `~/Library/Application Support/Deskling/KlavyeSesleri` altına açar. Alt klasörler de (üç kata kadar) okunur. Aynı paket birden çok yerde ya da iki kez indirilmişse (`paket (1).zip`) listede bir kez görünür: aynı kimlik ya da aynı ad ve yapımcı kopya sayılır, en yeni sürüm kalır. Panel kaç kopyanın atlandığını söyler. Bir pakette şunlardan biri varsa o paket açılmaz ve panelde nedeni yazar:

- Klasörün dışına çıkan dosya adları.
- Bağlantılar (symlink).
- Çok büyük dosyalar.
- Ses dışı dosyalar.

Mechvibes'ın 1. ve 2. sürüm paket biçimleri okunur: tek dosyalı ya da her tuşa ayrı dosyalı, tuş bırakma sesli ya da sessiz. Ogg, WAV ve MP3 dosyaları açılır.

**Lisans:** Her paketin lisansı panelde görünür. "Kişisel kullanım" lisanslı paketler yalnızca kendi bilgisayarında kullanılabilir; bu yüzden paketler projeye eklenmez ve hiçbir yere gönderilmez.

**Seçenekler:**

- **Tuş bırakma sesi:** Pakette varsa, tuşu bırakınca da ses çıkar.
- **Stereo:** Sol tuşlar soldan, sağdakiler sağdan duyulur.
- **Doğal çeşitlilik:** Her basışta perde ve ses biraz değişir, makineli tüfek gibi tekrar etmez.
- **Mikrofonda susma:** Mikrofon kullanılırken (toplantı, kayıt) sesler susar.

Basılı tutulan tuşun tekrarları ses çıkarmaz. Ses motoru önceden hazırlanmış sesleri 14 kanalda üst üste çalabilir. Yazmayı bırakınca 20 saniye sonra kapanır.

**Gizlilik:** Tuşları duymak için macOS'un **Giriş İzleme** izni gerekir. Deskling yalnızca hangi tuşa basıldığını anlar; yazılan metni okumaz, saklamaz, göndermez. Parola alanlarında macOS tuşları uygulamalara göstermez, o sırada ses çıkmaz. İzin verilmeden de panelin deneme alanında sesler dinlenebilir.

## Denetim paneli

<div align="center">
<img src="docs/images/panel.png" width="420" alt="Deskling denetim paneli">
</div>

Panele menü çubuğundaki yuvarlak simgeden ulaşırsın.

| Sekme | Ne yapar? |
| --- | --- |
| **Bulunanlar** | Masaüstündeki ekran görüntülerini listeler. Seçtiklerini toplatır, kilitlediklerine robot dokunmaz. |
| **Geçmiş** | Toplanan her dosyayı gösterir ve tek tıkla masaüstüne geri koyar. |
| **Portlar** | Dinlenen portlar ve Docker konteynerleri. |
| **Odak** | Pomodoro sayacı, içecek seçimi, süreler, görünüm ve robot/kar senkronu. |
| **Disk** | Disk analizi, parça parça grafik, silinebilir öneriler ve bellek temizleme. |
| **Klavye** | Klavye seslerini açma, paket seçme ve dinleme, ses düzeyi, paket klasörü ve seçenekler. |
| **Ada** | Dinamik adayı ve her etkinliği açıp kapatma, açılma gecikmesi ve davranışlar. |
| **Ayarlar** | Otomatik toplama süresi, robot hızı, hazne kapasitesi, kar, küreme aracı, halı boyutu, açılışta başlatma ve sesler. |

## Nasıl çalışır?

```mermaid
flowchart LR
    A[Çift tıklama] --> B[Masaüstünü tara]
    B --> C{Ekran görüntüsü var mı?}
    C -- Hayır --> D[Bir tur at]
    C -- Evet --> E[En yakın görüntüye git]
    E --> F[İçine çek]
    F --> G{Hazne doldu mu<br>ya da iş bitti mi?}
    G -- Hayır --> E
    G -- Evet --> H[Kutuya boşalt]
    H --> I{Kalan var mı?}
    I -- Evet --> E
    I -- Hayır --> J[İstasyona dön]
    D --> J
```

### Ekran görüntüsü nasıl anlaşılır?

Robot bir dosyayı almadan önce şu iki işaretten birini arar:

1. Spotlight'taki `kMDItemIsScreenCapture` kaydı
2. Görüntünün EXIF verisindeki `Screenshot` imzası

Adı "Ekran Resmi" olan sıradan bir görsel bu yüzden alınmaz.

### Dosyaların güvenliği

- Dosyalar yalnızca taşınır, uygulama hiçbir dosyayı silmez.
- Taşımadan hemen önce dosya yeniden doğrulanır. Tarandıktan sonra değişen dosyaya dokunulmaz.
- Kutuda aynı adlı dosya varsa üzerine yazılmaz, yeni dosya numaralandırılır.
- Alt klasörlere ve sembolik bağlantılara girilmez.
- Kilitlenen dosyalar hiçbir modda alınmaz.

Toplanan görüntüler şu klasörde durur:

```text
~/Library/Application Support/Deskling/Toz Haznesi
```

## Robo Süpürge'den geçiş

Uygulamanın eski adı Robo Süpürge'ydi. Deskling ilk açıldığında eski ayarları, toz haznesini, halının altındaki dosyaları, geçmişi ve pano kayıtlarını kendiliğinden yeni yerine taşır. Hiçbir şey silinmez. Uygulama kimliği değiştiği için macOS Masaüstü, Finder ve Erişilebilirlik izinlerini bir kez yeniden sorar.

## Kurulum

**Gereksinimler:** Apple Silicon işlemcili bir Mac, macOS 13 veya üzeri, Xcode Command Line Tools.

```bash
git clone https://github.com/furkandemirbozan/deskling.git
```

```bash
cd deskling
```

```bash
./build.sh
```

```bash
cp -R "Deskling.app" /Applications/
```

```bash
open /Applications/Deskling.app
```

### İzinler

İlk kullanımda macOS iki izin sorar. Üçüncüsü isteğe bağlıdır:

| İzin | Neden gerekli? |
| --- | --- |
| **Masaüstü klasörü** | Ekran görüntülerini bulmak için |
| **Finder otomasyonu** | Simgelerin yerini öğrenmek ve çarpılan simgeleri kaydırmak için |
| **Bildirimler** (isteğe bağlı) | Pomodoro süresi bitince haber vermek için |
| **Müzik / Spotify / tarayıcı otomasyonu** (isteğe bağlı) | Dinamik adada çalan parçanın kapağını, konumunu göstermek ve denetlemek için |
| **Giriş İzleme** (isteğe bağlı) | Klavye seslerinin hangi tuşa basıldığını duyabilmesi için. Yazılan metin okunmaz |
| **Erişilebilirlik** (isteğe bağlı) | Pano geçmişinden seçilen kaydı öndeki uygulamaya kendiliğinden yapıştırmak için |

Uygulama yerel olarak imzalandığı için her yeniden derlemeden sonra macOS izinleri yeniden sorabilir.

Finder izni verilmezse robot simgelerin yerini macOS'un varsayılan yerleşimine göre tahmin eder ve simgeleri itmez.

## Kullanım

| Yapmak istediğin | Nasıl? |
| --- | --- |
| Temizliği başlat | Robota **çift tıkla** |
| Toplananları gör | İstasyondaki kutuya **tek tıkla** |
| Paneli aç | Menü çubuğundaki simge → **Denetim Panelini Aç** |
| Dosyalara dokunmadan dene | Panel → **Demoyu izle** |
| Uygulamayı kapat | Menü çubuğundaki simge → **Çıkış** |

## Proje yapısı

```text
Sources/
├── Migration.swift  Robo Süpürge'den Deskling'e ayar ve veri geçişi
├── main.swift       Uygulama girişi ve menü çubuğu
├── AppModel.swift   Uygulama durumu, tarama ve görev yönetimi
├── Core.swift       Algılama, dosya taşıma ve masaüstü geometrisi
├── Engine.swift     Robotun hareket motoru
├── Motion.swift     Gezinti rotaları, simgelere çarpma ve içine çekme hareketi
├── MotionCheck.swift Hareket testleri
├── Overlay.swift    Masaüstü sahnesi, tıklama alanları ve animasyonlar
├── RobotArt.swift   Kodla çizilen robot, istasyon ve uygulama simgesi
├── PanelView.swift  SwiftUI denetim paneli
├── Rug.swift        Halı penceresi, katlama ve halı altı klasörü
├── RugArt.swift     Kodla dokunan Türk motifli halı
├── RugCheck.swift   Halının uçtan uca testi
├── Snow.swift       Kar penceresi, pencere takibi ve Metal çizimi
├── SnowEngine.swift Kar fiziği ve kar küreme aracı
├── SnowCheck.swift  Kar fiziği testleri
├── SnowSculpt.swift Kar topu, kardan adam, kar yığını ve yer çekimi
├── SculptCheck.swift Kar topu testleri
├── DevCenter/
│   ├── PortScanner.swift  Dinlenen portlar ve Docker
│   ├── DevCenter.swift    Portlar sekmesinin durumu ve işlemleri
│   ├── PortsView.swift    Portlar sekmesi
│   └── DevCheck.swift     Port ve Docker testleri
├── Clipboard/
│   ├── ClipItem.swift          Kayıt, tür algılama ve renk dönüşümleri
│   ├── ClipboardStore.swift    Pano takibi ve geçmiş
│   ├── HotKey.swift            Genel kısayol ve yapıştırma
│   ├── ClipboardPanel.swift    Yüzer pano penceresi
│   └── ClipboardCheck.swift    Pano testleri
├── Pomodoro/
│   ├── PomodoroManager.swift  Odak, kısa ve uzun mola durum makinesi
│   ├── PomodoroSettings.swift İçecek temaları, boyutlar ve ayar sınırları
│   ├── PomodoroModel.swift    Ayarlar, bildirim, ses ve uyanık tutma bağlantısı
│   ├── PomodoroAlerts.swift   Bildirim, ses ve ekranı uyanık tutma
│   ├── PomodoroTab.swift      Odak sekmesi
│   ├── DrinkController.swift  İçecek penceresi, sürükleme, sağ tık menüsü
│   ├── DrinkView.swift        Katmanlı, düşük yüklü çizim
│   ├── DrinkControlBar.swift  Üzerine gelince beliren kontrol çubuğu
│   ├── SloshPhysics.swift     Sıvının çalkalanması
│   ├── DrinkParticles.swift   Buhar, baloncuk, damla ve köpük izi
│   ├── DrinkArt.swift         Ortak çizim, önbellek ve dolum akışı
│   ├── TeaGlass.swift, TurkishCoffee.swift, CoffeeMug.swift, BeerPint.swift  İçecekler
│   ├── DrinkIcons.swift       Menü çubuğu simgeleri
│   └── PomodoroCheck.swift, PomodoroSyncCheck.swift, DrinkUICheck.swift  Testler
├── Island/
│   ├── IslandCore.swift        Çentik ölçüsü, yerleşim, ayarlar, zamanlayıcı ve üzerine gelme mantığı
│   ├── IslandManager.swift     Hangi etkinliğin görüneceği, bildirimler ve uyarılar
│   ├── IslandController.swift  Menü çubuğunun üstündeki pencere, fare takibi, tam ekran
│   ├── IslandSensors.swift     Pil, ses düzeyi ve çıkış aygıtı
│   ├── NowPlaying.swift        Müzik ve Spotify: parça, kapak, renk ve denetimler
│   ├── IslandShelf.swift       Dosya rafı
│   ├── IslandViews.swift, IslandExpanded.swift  Ada görünümleri
│   ├── IslandTab.swift         Ada sekmesi
│   ├── IslandModel.swift       Pomodoro, robot ve pano bağlantısı
│   └── IslandCheck.swift       Testler ve görsel galeri
├── Disk/
│   ├── DiskModel.swift         Bölümler, kararlar ve karar kuralları
│   ├── DiskScanner.swift       Salt okunur tarama ve Çöp Kutusu'na taşıma
│   ├── MemoryCenter.swift      Bellek sayaçları, uygulamaların belleği ve kapatma önerileri
│   ├── DiskViews.swift         Disk sekmesi, halka grafik ve parça çubuğu
│   ├── DevCleanup.swift        Docker artıkları, bin/obj ve node_modules taraması
│   └── DiskCheck.swift         Testler, salt okunur rapor ve görsel galeri
├── Keys/
│   ├── KeyCodes.swift          macOS tuş kodları, paketlerdeki tuş adları ve tuşların klavyedeki yeri
│   ├── SoundPack.swift         Mechvibes paketlerini okuma ve zip'leri güvenle açma
│   ├── KeySoundEngine.swift    Ses çözme ve kesme, dahili paketlerin sentezi, düşük gecikmeli çalar
│   ├── KeyListener.swift       Tuş dinleme (Giriş İzleme) ve mikrofon takibi
│   ├── KeySoundCenter.swift    Paketler, ayarlar ve klasör izleme
│   ├── KeysTab.swift           Klavye sekmesi
│   └── KeysCheck.swift         Testler ve salt okunur paket raporu
├── BlackHole/
│   ├── BlackHoleController.swift Kara delik penceresi, sürükle bırak ve animasyonlar
│   ├── HoleRenderer.swift        Işığı büken diskin Metal çizimi
│   ├── HoleProcessor.swift       ZIP, arşiv açma, JSON ve CSV işlemleri
│   ├── HoleMedia.swift           Görsel ve PDF işlemleri
│   ├── HoleVideo.swift           Video sıkıştırma, ses ayırma ve GIF
│   ├── HoleVideoCheck.swift      Video testleri
│   ├── HoleMediaCheck.swift      Görsel ve PDF testleri
│   ├── HoleCheck.swift           İşlem ve görünüm testleri
│   └── HoleUICheck.swift         Kara delik penceresinin uçtan uca testi
└── SelfTest.swift   Otomatik testler
build.sh             .app paketini derler ve imzalar
```

## Testler

Testler geçici klasörlerde çalışır, gerçek masaüstüne dokunmaz.

```bash
Deskling.app/Contents/MacOS/Deskling --self-test
```

```bash
Deskling.app/Contents/MacOS/Deskling --double-click-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --patrol-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --auto-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --rug-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --snow-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --motion-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --sculpt-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --hole-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --hole-ui-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --dev-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --clip-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --migration-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --pomo-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --pomo-sync-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --drink-ui-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --island-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --rug-lock-check
```

```bash
Deskling.app/Contents/MacOS/Deskling --disk-check
```

`--disk-check`, sahte bir ev klasöründe ve sahte Docker çıktısıyla tarar. Çöp Kutusu'na taşımayı da sahte bir klasörle dener. Gerçek dosyalara ve uygulamalara dokunmaz.

Gerçek diskte yalnızca okuyarak bir özet görmek için şunu kullan; uygulamalar, önbellekler, günlükler ve bellek listelenir:

```bash
Deskling.app/Contents/MacOS/Deskling --disk-report
```

```bash
Deskling.app/Contents/MacOS/Deskling --keys-check
```

`--keys-check`, geçici klasörlerde çalışır. Kontrol ettikleri:

- Sahte zip'ler, bağlantı içeren ve bozuk paketler.
- Ses kesme.
- Dahili paketler.
- Tuş eşlemesi.

Gerçek paket klasörüne dokunmaz, tuş dinlemez, ses çalmaz. Bir klasördeki paketlerin hepsinin açılıp açılmadığını görmek için şunu kullan; paketler geçici bir yere açılır ve hiçbir şey değişmez:

```bash
Deskling.app/Contents/MacOS/Deskling --keys-report ~/Documents/KlavyeSesDosyaları
```

Adanın bütün durumlarını PNG olarak çizmek için:

```bash
Deskling.app/Contents/MacOS/Deskling --island-gallery /tmp/ada
```

## Bilinen sınırlar

- Robot, halı ve kar yalnızca ana ekranda çalışır.
- Masaüstünde "Izgaraya hizala" veya otomatik sıralama açıksa Finder itilen simgeleri kendi düzenine geri çekebilir.
- Kar açıkken uygulama işlemcinin yaklaşık %8-10'unu kullanır. Masaüstündeki içecek yüksek animasyonda yaklaşık %5, düşükte %2-3 ekler.
- macOS 15.4'ten beri sistemin "şu an çalan" bilgisi Apple dışındaki uygulamalara kapalı. Dinamik ada bu yüzden Müzik ve Spotify'ı kendi bildirimlerinden, tarayıcıları sekmelerden okur. Firefox'ta yalnızca öndeki sekmenin başlığı görünür; desteklenen sitelerin dışındaki sekmelerde çalan ses görünmez.
- Ada, sistemin kendi ses göstergesinin yerine geçmez; ikisi birlikte görünür.
- Disk taramasında macOS, İndirilenler ve Belgeler için bir kez izin ister. Mail, Mesajlar ve Safari gibi korumalı klasörler Tam Disk Erişimi olmadan ölçülmez; bunlar "Sistem ve diğer" içinde kalır.
- Uygulamaların "son açılma" bilgisi Spotlight'tan gelir. Spotlight'ın kaydı yoksa uygulama en fazla "gözden geçir" olur.
- Derleme betiği yalnızca Apple Silicon (arm64) için paket üretir.
- Mac açılışında başlatma yalnızca `/Applications` klasöründeki kopyada çalışır.
