# Ręczny druk dwustronny PDF na HP LaserJet 1020

Aplikacja macOS (13+) napisana w Swift/AppKit/PDFKit. Korzysta z zainstalowanej kolejki CUPS i oryginalnego sterownika z tego repozytorium. Nie wymaga Pythona ani dodatkowych bibliotek. Wymaga Xcode Command Line Tools do zbudowania (`xcode-select --install`).

## Uruchomienie

Najpierw zainstaluj sterownik i dodaj drukarkę według głównego README. Następnie, w katalogu repozytorium:

```sh
sh manual-duplex/build.sh
open "manual-duplex/build/HP1020 Manual Duplex.app"
```

1. Wybierz PDF. Z innych aplikacji zapisz dokument jako PDF w oknie drukowania.
2. Wybierz kolejkę HP 1020, format A4 lub Letter i oprawę. Domyślna oprawa jest przy długiej krawędzi; opcja krótkiej krawędzi obraca tyły o 180°. Strony są dopasowane do papieru.
3. Kliknij „Drukuj pierwsze strony”. Aplikacja wyśle strony 1, 3, 5… jako osobne zadanie jednostronne.
4. Monit pojawia się po przyjęciu zadania przez CUPS. To **nie oznacza fizycznego zakończenia druku**. Poczekaj na wszystkie kartki i sprawdź kompletność wydruku.
5. Wyjmij czysty papier z podajnika i przełóż stos zgodnie z monitem: zadrukowaną stroną w dół, dolną krawędzią do drukarki. Zachowaj kolejność: ostatnia nieparzysta strona ma być pobrana pierwsza.
6. Kliknij „Papier przełożony — drukuj drugą stronę”. Dopiero teraz drugie zadanie trafia do drukarki.

Nie wysyłaj innych zadań podczas obu przebiegów. Aplikacja nie blokuje kolejki dla innych użytkowników. Najpierw sprawdź 4-stronicowy dokument z dużymi numerami i oznaczeniem góry strony, następnie 5-stronicowy. Zweryfikuj pary 1/2, 3/4, 5/pusta oraz kierunek oprawy. Fizyczne zachowanie sterownika i drukarki wymaga takiego testu.

Sposób wkładania papieru: [HP LaserJet 1020 User Guide, strony 32–33](https://h10032.www1.hp.com/ctg/Manual/c00264334.pdf). Przy nietypowym obrocie stron źródłowego PDF sprawdź kierunek oprawy na próbce.

## Kolejność i nieparzysta liczba stron

Dla 5 stron przody to `[1, 3, 5]`, a tyły `[pusta, 4, 2]`. Pusta strona przechodzi przez drukarkę, aby nie przesunąć par. Dla jednej strony nie ma drugiego przebiegu. Każde uruchomienie drukuje jedną kopię całego PDF, po jednej stronie na arkusz. Zakresy stron i wiele kopii przygotuj wcześniej w osobnym PDF albo uruchom aplikację ponownie.

„Anuluj” w monicie zapobiega wysłaniu tyłów. Już wysłane zadanie anuluj w kolejce drukowania macOS. Gdy pierwszy przebieg był anulowany, wystąpiło zacięcie lub brakuje kartek, anuluj drugi przebieg i zacznij od nowa z kompletnym stosem.

Pliki robocze są zapisywane w prywatnym, losowym katalogu tymczasowym i usuwane przy normalnym zakończeniu. CUPS zachowuje własne pliki zgodnie ze swoimi ustawieniami. Aplikacja nie wysyła dokumentu do zewnętrznych usług.

## Sprawdzenie kodu

```sh
sh manual-duplex/build.sh
"manual-duplex/build/HP1020 Manual Duplex.app/Contents/MacOS/HP1020ManualDuplex" --self-test
```

Test nie drukuje. Sprawdza parowanie dla 1–101 stron, pusty tył, zapis/odczyt PDF, obrót i zachowanie oryginału. Nie zastępuje testu na urządzeniu. Aplikacja jest kompilowana dla architektury bieżącego Maca; Intel i Apple Silicon budują ten sam kod osobno.
