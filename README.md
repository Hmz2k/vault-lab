# Vault Lab

I dette prosjektet satte jeg opp HashiCorp Vault og en PostgreSQL database i Docker på min egen maskin. Målet var å lære hvordan man lagrer passord og andre hemmeligheter på en trygg måte, og å se hvor ting fortsatt kan gå galt selv når man bruker et verktøy som er laget for nettopp dette.

Underveis fant jeg to måter passordene mine kunne lekke på, og fikset begge. Til slutt lot jeg Vault lage databasepassord som slettes av seg selv etter kort tid.

Alle passord i prosjektet er falske og laget bare for testing.

## Hvorfor

Lekkede passord er en av de vanligste årsakene til innbrudd. I mange bedrifter ligger passord rett i koden eller i konfigurasjonsfiler, flere personer deler det samme passordet, og det blir sjelden byttet. Når noe først lekker, er det ofte vanskelig å vite hvem som har brukt det og hvor lenge.

Vault prøver å løse dette ved å samle alle hemmeligheter på ett sted, styre hvem som får hente hva, og logge alt som skjer. Jeg ville se hvordan det fungerer i praksis, og hva man selv må passe på.

## Oppsett

* Vault 1.20 i Docker, bare tilgjengelig fra min egen maskin
* PostgreSQL 17 i Docker, bare tilgjengelig inne i Docker nettverket og ikke utenfra
* Tilgangsreglene ligger som filer i mappen `policies/`, slik at endringer kan følges i Git
* Kjørt på Windows 11 med WSL, Ubuntu og Docker

## 1. Vault i utviklermodus

![Vault status](docs/bilder/01_devmodus_status.png)

Jeg startet Vault i utviklermodus fordi det er den enkleste måten å komme i gang på. Statusen viser tre ting som gjør at denne modusen bare passer for testing:

* **Sealed false:** Vault er åpen fra start. I et ekte oppsett starter den låst, og må låses opp før noen kan bruke den.
* **Threshold 1:** én nøkkel er nok til å låse opp. I et ekte oppsett deles nøkkelen i flere deler, slik at ingen kan åpne Vault alene.
* **Storage Type inmem:** alt ligger i minnet. Stopper containeren, forsvinner alle hemmelighetene.

Jeg la også merke til at utviklermodus skriver både hovednøkkelen og root tokenet rett ut i loggen. Det var en påminnelse om at logger også kan inneholde passord, og at man bør se over dem før man deler dem med noen.

## 2. Ingen tilgang uten token

![Nektet uten token](docs/bilder/02_uten_token_nektet.png)

Første gang jeg prøvde å lagre et passord, fikk jeg feilmeldingen 403. Jeg hadde ikke logget inn, så Vault visste ikke hvem jeg var og nektet alt. Det interessante var at kommandoen ble stoppet før den i det hele tatt kom så langt som å lagre noe. Vault stenger alt som standard, og åpner bare for det noen eksplisitt har fått lov til.

Jeg løste det ved å logge inn med `vault login`. Da skriver man tokenet inn uten at det vises på skjermen, og det havner ikke i kommandohistorikken.

## 3. Root token

![Root token](docs/bilder/03_root_token.png)

Etter innloggingen viser Vault hvilke rettigheter tokenet har. Root tokenet har full tilgang til alt og utløper aldri. Det gjør det til det mest verdifulle en angriper kan få tak i. I et ekte oppsett bruker man det bare til å sette opp Vault, og så trekkes det tilbake. Senere i prosjektet lager jeg egne tokens som har mindre tilgang og kort levetid.

Jeg har skjult `token_accessor` på bildet. Den gir ikke tilgang i seg selv, men kan brukes til å slå opp tokenet, og sånt vil jeg ikke dele offentlig.

## 4. Lagre og hente et passord

![Passord lagret og hentet](docs/bilder/04_hemmelighet_lagret.png)

Jeg lagret et databasepassord for en tenkt nettbutikk og hentet det ut igjen. Vault svarte med stien `secret/data/nettbutikk/database`, selv om jeg skrev `secret/nettbutikk/database`. Vault legger til `data/` selv, fordi den holder selve verdiene og informasjonen om dem hver for seg. Det var noe jeg måtte huske på senere, da jeg skrev tilgangsreglene.

En app trenger vanligvis bare selve passordet, så jeg testet også å hente ut bare verdien med `kv get -field=passord`.

## 5. Det gamle passordet fantes fortsatt

![Gammelt passord](docs/bilder/05_gammelt_passord_hentes.png)

Jeg byttet passordet fra `Sommer2026` til `Host2026`. Vault overskrev ikke det gamle, men lagret det nye som en ny versjon. Da jeg ba om versjon 1, fikk jeg det gamle passordet ut i klartekst.

Vault tar vare på opptil ti gamle versjoner av hvert passord. Det er nyttig hvis et bytte går galt og man må tilbake. Men hvis passordet ble byttet fordi det hadde lekket, ligger det lekkede passordet fortsatt der for alle som har lesetilgang. Da er ikke jobben gjort før den gamle versjonen er slettet.

## 6. Passordene lå i kommandohistorikken

![Passord i historikken](docs/bilder/06_passord_i_historikk.png)

Denne overrasket meg. Jeg hadde skrevet passordene rett inn som en del av kommandoene, og terminalen lagrer alle kommandoer i filen `~/.bash_history`. Begge passordene lå der i klartekst. Hvem som helst med tilgang til brukeren min kunne lest dem, uten å røre Vault i det hele tatt.

Jeg trodde først at `clear` ville hjelpe, men den tømmer bare skjermen. Historikken er urørt. Vault beskytter passordet fra det øyeblikket det er lagret, men ikke på veien inn.

## 7. Fikset

![Fikset](docs/bilder/07_utbedring_verifisert.png)

Jeg slettet den gamle versjonen for godt med `kv destroy`. Det er forskjellig fra `kv delete`, som bare skjuler versjonen og kan angres. I tillegg satte jeg Vault til å bare ta vare på to versjoner. Da jeg senere lagret et nytt passord, forsvant versjon 1 helt, og bildet viser at den ikke lenger finnes.

I historikken fant jeg faktisk tre passord, ikke to som jeg trodde. Det tredje kom fra kommandoen som feilet med 403 i steg 2. Kommandoer blir altså lagret selv om de feiler. Etter dette søkte jeg systematisk etter passord i stedet for å stole på hukommelsen, og slettet alle tre. Nå leser jeg passord inn med `read -s`, som skjuler det jeg skriver, og sender det videre gjennom en variabel. Da står bare variabelnavnet i historikken.

## 8. Appen får bare det den trenger

![Appen leser sitt eget passord](docs/bilder/08_policy_tillater.png)

Jeg skrev en tilgangsregel for nettbutikken som bare gir lov til å lese passordene under `nettbutikk`. Regelen ligger i filen `policies/nettbutikk.hcl`. Så lagde jeg et token med denne regelen som varer i 15 minutter. Med det tokenet kunne appen lese sitt eget databasepassord, akkurat som den skal.

![Appen blir nektet](docs/bilder/09_policy_nekter.png)

Deretter prøvde jeg to ting appen ikke skal kunne gjøre. Den fikk ikke lese betalingsnøkkelen, fordi den stien ikke står i regelen. Den fikk heller ikke endre sitt eget passord, fordi regelen bare gir lesetilgang. Hvis appen blir hacket, får angriperen altså ikke tilgang til andre systemer, og kan ikke bytte passordet for å låse ute de som skal bruke det.

## 9. Tokenet slutter å virke

![Tokenet er utløpt](docs/bilder/10_token_utlopt.png)

For å se at tokens faktisk utløper, lagde jeg et token som bare varer i 30 sekunder. Klokka 14:52:45 kunne det lese passordet. Etter 35 sekunder fikk jeg `invalid token` på nøyaktig samme kommando.

Feilmeldingen er annerledes enn i steg 8. Der var tokenet gyldig, men hadde ikke lov. Her finnes ikke tokenet lenger i det hele tatt. Et stjålet token med kort levetid gir en angriper veldig lite tid.

## 10. Logg over hvem som hentet hva

![Loggen](docs/bilder/11_revisjonslogg.png)

Jeg slo på loggen i Vault og gjentok de to forsøkene fra appen. Loggen viste begge, med tidspunkt, hvilken sti det gjaldt og hvilken tilgang tokenet hadde. Forsøket som gikk gjennom står uten feil, og forsøket på betalingsnøkkelen står med `permission denied`. I en ekte hendelse er det sånn man finner ut hva en hacket app har prøvd å hente.

Jeg søkte også etter passordet i loggfilen, men fant det ikke. Vault gjør om passordene før de skrives til loggen, så loggen viser at noe ble hentet, uten at den selv blir et nytt sted passordet kan lekke fra.

## 11. Databasepassord som slettes av seg selv

![Innlogging med passord fra Vault](docs/bilder/12_dynamisk_passord.png)

Til slutt koblet jeg Vault til databasen. I stedet for ett fast passord som alle deler, lager Vault en ny databasebruker hver gang noen ber om det. Brukeren kan bare lese, og varer i to minutter. Jeg lot også Vault bytte adminpassordet til databasen, så nå er det bare Vault som kjenner det. Ingen person kan logge inn som admin lenger.

Jeg logget inn fra en egen container på samme nettverk, slik en app ville gjort. Brukernavnet ble laget av Vault i samme øyeblikk, og passordet ble aldri vist på skjermen.

![Passordet virker ikke lenger](docs/bilder/13_passord_utlopt.png)

Etter to minutter prøvde jeg igjen med samme bruker, og ble avvist. Et lekket passord blir dermed ubrukelig av seg selv, uten at noen må oppdage lekkasjen og bytte det først. Jeg la også merke til at databasen gir samme feilmelding uansett om brukeren finnes eller ikke, så en angriper kan ikke bruke feilmeldingen til å finne gyldige brukernavn.

## Det jeg lærte

Det meste som gikk galt, var ikke Vault sin feil, men hvordan jeg brukte det. Passordene lekket gjennom terminalen før de i det hele tatt kom inn i Vault. Det var den viktigste lærdommen for meg.

Jeg lærte også at det å bytte et passord ikke betyr at det gamle er borte, og at kommandoer som feiler også lagres i historikken. Feilmeldingene viste seg å si mye. `permission denied` betyr at man mangler tilgang, mens `invalid token` betyr at tokenet ikke finnes lenger.

Det jeg likte best var passord og tokens som utløper av seg selv. Da blir en lekkasje mye mindre farlig, fordi det som lekker slutter å virke uansett.

Jeg gjorde også noen småfeil underveis, som å skrive `wsl -install` med én bindestrek, glemme `apt update`, og oppleve at `read -s` tok imot neste linje jeg limte inn som passord. Alle ble løst, og de lærte meg mye om hvordan verktøyene faktisk fungerer.

## Begrensninger

Dette er en lab og ikke et ekte oppsett. Vault kjører i utviklermodus med alt i minnet, trafikken mellom delene er ikke kryptert, og root tokenet er satt til en kjent verdi i `compose.yaml`.

## Videre

Hvis jeg skulle bygget videre, ville jeg:

* satt opp Vault ordentlig, låst ved oppstart og med nøkkelen delt på flere personer
* trukket tilbake root tokenet etter oppsett
* kryptert trafikken mellom alle delene
* sendt loggen til et overvåkingssystem som varsler når noen blir nektet mange ganger

## Kjør selv

Du trenger Docker med Compose.

```bash
git clone https://github.com/Hmz2k/vault-lab.git
cd vault-lab

read -s -p "Database adminpassord: " PG
echo "POSTGRES_PASSWORD=$PG" > .env
unset PG
chmod 600 .env

docker compose up -d
docker exec -it vault vault login
docker exec -i vault vault policy write nettbutikk - < policies/nettbutikk.hcl
docker exec vault vault audit enable file file_path=/tmp/vault_audit.log
```

Resten av stegene, inkludert oppsettet av databasen, står i [ARBEIDSLOGG.md](ARBEIDSLOGG.md).

## Rydde opp

```bash
docker compose down
```

Siden Vault kjører i utviklermodus og databasen ikke lagrer noe varig, forsvinner alt når containerne fjernes.
