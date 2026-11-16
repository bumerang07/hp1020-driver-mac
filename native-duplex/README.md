# HP LaserJet 1020 — natywny ręczny dupleks (prototyp)

Drukowanie przez standardowe **⌘P**. **Ręczny dupleks przy długiej krawędzi jest domyślnie włączony**, także dla zadań bez jawnej opcji; druk jednostronny wymaga wybrania **Off**. Opcja **Manual Two-Sided Printing** w funkcjach drukarki, automatyczny monit po pierwszym przebiegu, przycisk kontynuacji. Nie trzeba zapisywać PDF ani uruchamiać aplikacji do drukowania.

**Status:** skompilowany prototyp z testami syntetycznymi. Niezweryfikowany jeszcze na fizycznym HP 1020 ani wewnątrz rzeczywistego łańcucha CUPS na docelowym Macu. Wyświetlenie opcji przez poszczególne aplikacje macOS, transmisja USB, sandbox i kierunek przełożenia papieru wymagają próby integracyjnej. Nie traktuj tego jako gotowego, certyfikowanego sterownika.

## Instalacja

Wymagania: macOS 13+, działająca drukarka skonfigurowana z oryginalnym sterownikiem z głównego README, lokalnie zalogowany użytkownik. Instalacja zmienia **PPD istniejącej kolejki**, zachowując jej nazwę i połączenie USB. Wybierz pustą kolejkę bez aktywnych zadań.

Z kodu źródłowego (Xcode Command Line Tools i Python 3 potrzebne tylko do budowania):

```sh
sh native-duplex/build.sh
sudo sh native-duplex/install.sh HP_LaserJet_1020
```

Podstaw własną nazwę kolejki z `lpstat -e`. W gotowej paczce ZIP są już pliki dla Apple Silicon: rozpakuj i uruchom **Install.command**, który zapyta o kolejkę oraz hasło administratora. Nie uruchamiaj instalatora z konta root — użyj `sudo` ze swojego konta.

Instalator dodaje filtr do `/Library/Printers/HP1020Duplex`, automatycznie uruchamiany komponent monitu do `/Library/LaunchAgents` i zapisuje kopię oryginalnego PPD. Nie zmienia SIP ani ustawień sandboxa CUPS. Komponent monitu uruchamia się po zalogowaniu i nie pokazuje osobnego głównego okna.

## Użycie

1. Zamknij i otwórz ponownie okno drukowania w aplikacji.
2. Wybierz dotychczasową drukarkę HP 1020.
3. Rozwiń **Funkcje drukarki / Printer Features**, grupę **HP 1020 Printing**. Umiejscowienie zależy od aplikacji i wersji macOS.
4. W **Manual Two-Sided Printing** wybierz **On - Long Edge** albo **On - Short Edge**. Domyślnie włączone jest **On - Long Edge** (długa krawędź). **Off** wybiera druk jednostronny. To własna opcja sterownika, nie systemowy przełącznik automatycznego dupleksu.
5. Kliknij **Drukuj**. Po wysłaniu przodów pojawi się monit. Poczekaj na WSZYSTKIE kartki, przełóż stos według monitu i dopiero wtedy kliknij **Kontynuuj**.

Monit nie jest potwierdzeniem fizycznego zakończenia drukowania: sterownik może opróżnić bufor transmisji, ale HP 1020 nadal może drukować. Użytkownik potwierdza kompletność i zakończenie pierwszego przebiegu. Monit jest aktywowany na pierwszym planie, korzysta z poziomu okna modalnego, nie ukrywa się przy przełączeniu aplikacji i może pojawiać się na wszystkich Spaces. Ograniczenia systemowych ekranów bezpieczeństwa nadal obowiązują.

W pierwszej próbie użyj 4 stron z dużymi numerami i oznaczeniem góry. Sprawdź pary 1/2, 3/4 oraz kierunek oprawy. Następnie sprawdź 5 stron: ostatni tył ma być pusty. Dla przełożenia stosu dolną krawędzią do drukarki długa krawędź obraca raster tyłów o 180°, a krótka pozostawia go bez obrotu. Mapowanie skorygowano po pierwszej udanej próbie na fizycznym HP 1020, w której tył był odwrócony. Instrukcja przełożenia opiera się na [podręczniku HP, s. 32–33](https://h10032.www1.hp.com/ctg/Manual/c00264334.pdf).

Anulowanie monitu pomija tyły **i pozostałe kopie**. Dane już wysłane do drukarki mogą się wydrukować. Anulowanie całego zadania w systemowej kolejce przerywa filtr i usuwa żądanie monitu. Konwerter HP i jego procesy potomne dostają SIGTERM; jeśli nie kończą się w ciągu 2 sekund, filtr używa SIGKILL. Pojedynczy przebieg konwersji ma również limit 30 minut. Anulowanego przebiegu nie wznawiamy automatycznie: po zacięciu lub anulowaniu należy rozpocząć od nowa z kompletnym stosem. Po zacięciu lub niekompletnym wydruku anuluj zadanie i rozpocznij od nowa.

## Jak działa

- Generator PPD zachowuje ustawienia oryginalnego sterownika i podmienia wyłącznie filtr rastra. Dodaje własną opcję dupleksu, obsługę kopii oraz poprawia dwa błędne znaczniki `CloseUI` przy opcjach `JCLOpenUI` w źródłowym PPD.
- Przy **Off** filtr bezpośrednio uruchamia oryginalny `rasterToHPZJS`, bez zmiany danych.
- Przy dupleksie filtr czyta raster po systemowym przygotowaniu dokumentu. Przechowuje go w prywatnych, od razu odłączonych od katalogu plikach tymczasowych. Do oryginalnego konwertera HP przekazuje dane przez nieblokujący potok, tak jak standardowy łańcuch CUPS — zwykły plik na standardowym wejściu konwertera powodował zawieszenie po pierwszej stronie. Wysyła nieparzyste strony przez oryginalny konwerter HP, czeka na potwierdzenie i wysyła parzyste w odwrotnej kolejności. Przy 5 stronach to `[1,3,5]`, potem `[pusta,4,2]`.
- Oba przebiegi pozostają **jednym zadaniem CUPS z tym samym backendem USB**. Zadania tej samej kolejki nie mogą wejść pomiędzy nie. Nie używaj równolegle drugiej kolejki prowadzącej do tego samego USB ani innego komputera sterującego drukarką.
- Dla wielu kopii każda kopia ma własny monit. Zakończony stos wyjmij przed wydrukiem następnej kopii.
- Komponent AppKit działający w sesji użytkownika odczytuje wyłącznie metadane: identyfikator zadania, liczbę stron i kopii. Nie otrzymuje dokumentu ani jego tytułu. Filtr nie ma dostępu do pulpitu użytkownika, dlatego okno pokazuje osobny proces działający automatycznie.
- Protokół plikowy używa losowych identyfikatorów i katalogu `/Users/Shared/hp1020-duplex-UID` z prawami `1733`. Potwierdzenia muszą należeć do użytkownika zadania, żądania do `_lp` lub root; dowiązania są odrzucane. Katalog nie pozwala innym użytkownikom listować nazw. Mechanizm heartbeat wykrywa brak komponentu przed pierwszym wydrukiem. Timeout oczekiwania: 30 minut.

## Ograniczenia prototypu

Obsługiwany jest monochromatyczny raster CUPS 1-bitowy albo 8-bitowy, maksymalnie 5000 stron, 4 GiB danych wejściowego rastra i 100 kopii. Inne formaty są odrzucane przed drukowaniem. Pliki przodów i tyłów wymagają dodatkowego miejsca na dysku (łącznie z wejściem do około dwukrotności rozmiaru rastra). Oryginalne binaria i firmware HP nadal są potrzebne; nie są zastąpione otwartym kodem. Kod wrappera i monitu jest nowy.

Zadania sieciowe bez odpowiadającego lokalnego konta z aktywnym komponentem monitu nie są obsługiwane. Prototyp instaluje się dla jednej kolejki, a launch agent startuje w sesjach Aqua. Etykiety nowej opcji w oknie drukowania są angielskie; monit jest po polsku. Pakiet nie jest notaryzowany. Natywny monit sprawdzono w trybie podglądu; opcja `--preview` komponentu monitu pozwala zobaczyć go bez drukowania i bez instalacji. Nie wykonano testów Intel; budowanie lokalne wybiera architekturę bieżącego Maca.

## Testy bez drukowania

```sh
sh native-duplex/build.sh
python3 native-duplex/tests/test_filter.py
"native-duplex/build/HP1020 Duplex Agent.app/Contents/MacOS/HP1020DuplexAgent" --self-test
cupstestppd -W filters native-duplex/build/HP1020-ManualDuplex.ppd
```

Test filtra uruchamia prawdziwy kod C i bibliotekę rastra CUPS. Konwerter HP zastępuje programem testowym, a kliknięcie użytkownika odpowiedzią protokołu. Sprawdza parowanie, pusty tył, obrót 1/8 bit z niepełnym ostatnim bajtem i paddingiem, kopie, anulowanie, SIGTERM, timeout, brak agenta, ucięty raster oraz tryb jednostronny. Nie ma połączenia z drukarką. Test sprawdza też, że konwerter dostaje na wejściu potok, a nie plik.

Dodatkowy `tests/test_real_converter.py PATH_TO_SYNTHETIC_ONE_PAGE_RASTER` testuje dwa przebiegi z rzeczywistym, zainstalowanym konwerterem HP i symulacją potwierdzenia. Nie uruchamia backendu USB; cały strumień drukarki przechwytuje w pamięci. Wymaga działającego komponentu monitu oraz wejściowego, jednostronicowego rastra testowego CUPS. Nie podawaj rastra wielostronicowego.

Walidator PPD ostrzega o niezainstalowanym jeszcze filtrze, brakującej ikonie z oryginalnego pakietu HP i dwóch odziedziczonych nazwach. `-W filters` pozwala sprawdzić PPD przed instalacją. Te ostrzeżenia nie są testem integracji CUPS.

## Aktualizacja po błędzie dostępu do monitu lub zawieszeniu konwertera

Wersja początkowa miała błędne uprawnienia komunikacji między kontem `_lp` a użytkownikiem. Poprawka otwiera katalog w trybie wyszukiwania (`O_SEARCH`) i udostępnia `_lp` odczyt metadanych heartbeat/odpowiedzi (0644). Nie udostępnia dokumentów ani listowania katalogu.

Po zbudowaniu poprawionej wersji:

```sh
sudo sh native-duplex/update.sh
```

Skrypt wymienia zainstalowany filtr i komponent monitu, uruchamia go ponownie i sprawdza dostęp z konta `_lp`. Nie usuwa, nie wznawia ani nie wysyła ponownie zadań drukowania. Dopuszcza zachowane zadania wstrzymane po błędzie, ale wymaga bezczynnej lub wyłączonej kolejki.

## Przywrócenie poprzedniego sterownika

Poczekaj na zakończenie lub anuluj aktywne zadania. Uruchom **Uninstall.command** albo:

```sh
sudo sh native-duplex/uninstall.sh
```

Skrypt przywraca PPD, usuwa automatyczny start i pliki nowego filtra/monitu. Zachowuje oryginalny sterownik HP i zapasowy PPD w `/Library/Printers/HP1020Duplex/backups`. Katalogi metadanych w `/Users/Shared` pozostają; nie zawierają dokumentów.

Podstawa integracji: [CUPS Filter and Backend Programming](https://www.cups.org/doc/api-filter.html), [CUPS PPD Extensions](https://www.cups.org/doc/spec-ppd.html). Projekt [foo2zjs](https://github.com/OpenPrinting/foo2zjs) był rozważany jako otwarta alternatywa, ale ten prototyp wykorzystuje już działający konwerter HP zamiast dokładać nowy silnik konwersji.
