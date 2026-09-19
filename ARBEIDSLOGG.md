# Arbeidslogg

Løpende notater fra arbeidet, med kommandoer, feil og funn i den rekkefølgen de skjedde.

## Forberedelser

* Installerte WSL 2 og Ubuntu, deretter Docker og Docker Compose med `apt`
* Feil: skrev `wsl -install` med én bindestrek, riktig er `wsl --install`
* Feil: `apt` fant ikke `docker.io` fordi jeg hoppet over `sudo apt update`
* Feil: `permission denied` mot `/var/run/docker.sock`. Løst med `sudo usermod -aG docker $USER` og ny innlogging (`wsl --shutdown`)
* Merknad: medlemskap i docker gruppen gir i praksis administratortilgang til maskinen

## Vault i utviklermodus

* Startet Vault 1.20 med `docker compose up -d`, port bundet til `127.0.0.1`
* `vault status`: Sealed false, Threshold 1, Storage Type inmem
* Funn: utviklermodus skriver unseal key og root token i klartekst i loggen

## Første hemmelighet

* Feil: `kv put` ga 403 fordi jeg ikke var logget inn
* Løst med `docker exec -it vault vault login`, tokenet skrives skjult
* Root token har policy root og utløper aldri

```bash
docker exec vault vault kv put secret/nettbutikk/database brukernavn=app passord=Sommer2026
docker exec vault vault kv get secret/nettbutikk/database
docker exec vault vault kv get -field=passord secret/nettbutikk/database
```

## Versjoner og historikk

* Byttet passord til Host2026 (versjon 2)
* Funn: `kv get -version=1` viste fortsatt Sommer2026
* Funn: begge passordene sto i klartekst i `history`
* Funn: også den feilede 403 kommandoen lå i historikken

Utbedring:

```bash
docker exec vault vault kv destroy -versions=1 secret/nettbutikk/database
docker exec vault vault kv metadata put -max-versions=2 secret/nettbutikk/database
history | grep passord=
history -d <nummer>
history -w
```

Ny metode for å lagre passord:

```bash
read -s -p "Nytt passord: " PASSORD
docker exec vault vault kv put secret/nettbutikk/database brukernavn=app passord="$PASSORD"
unset PASSORD
```

## Policyer

* Lagret betalingsnøkkel under `secret/betaling/api` med samme metode
* Skrev `policies/nettbutikk.hcl` med kun `read` på `secret/data/nettbutikk/*`

```bash
docker exec -i vault vault policy write nettbutikk - < policies/nettbutikk.hcl
APP_TOKEN=$(docker exec vault vault token create -policy=nettbutikk -ttl=15m -field=token)
docker exec -e VAULT_TOKEN="$APP_TOKEN" vault vault kv get secret/nettbutikk/database
docker exec -e VAULT_TOKEN="$APP_TOKEN" vault vault kv get secret/betaling/api
docker exec -e VAULT_TOKEN="$APP_TOKEN" vault vault kv put secret/nettbutikk/database passord=hacket
```

* Tillatt: lese eget passord
* Nektet: lese `betaling/api` (sti ikke i policy)
* Nektet: skrive til eget passord (kun read)

## Token utløper

* Token med `-ttl=30s` leste passord kl 14:52:45
* Etter `sleep 35`: 403 med `invalid token`
* Forskjell: policy gir `permission denied`, utløpt token gir `invalid token`

## Revisjonslogg

```bash
docker exec vault vault audit enable file file_path=/tmp/vault_audit.log
sudo apt install -y jq
docker exec vault cat /tmp/vault_audit.log | jq -c 'select(.type=="response" and (.request.path | startswith("secret/data"))) | {tid: .time, sti: .request.path, operasjon: .request.operation, policies: .auth.policies, feil: .error}' | tail -2
docker exec vault cat /tmp/vault_audit.log | grep -c goat
```

* Tillatt og nektet forsøk registrert med tid, sti og policy
* `grep -c goat` ga 0: sensitive verdier lagres som HMAC

## Dynamiske databasepassord

* La til PostgreSQL 17 i `compose.yaml` uten eksponerte porter
* Adminpassord i `.env` med `chmod 600`, lagt i `.gitignore`
* Feil: `read -s` tok imot neste innlimte linje som passord. Kommandoer med `read` må kjøres alene

```bash
docker exec vault vault secrets enable database

source .env
docker exec vault vault write database/config/nettbutikk \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/nettbutikk?sslmode=disable" \
  allowed_roles="app" \
  username="vaultadmin" \
  password="$POSTGRES_PASSWORD"
unset POSTGRES_PASSWORD

docker exec vault vault write database/roles/app \
  db_name=nettbutikk \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl=2m \
  max_ttl=5m

docker exec vault vault write -force database/rotate-root/nettbutikk
```

* Etter `rotate-root` virker ikke passordet i `.env` lenger, kun Vault kjenner det

Test:

```bash
CREDS=$(docker exec vault vault read -format=json database/creds/app)
DB_USER=$(echo "$CREDS" | jq -r .data.username)
DB_PASS=$(echo "$CREDS" | jq -r .data.password)
docker run --rm --network vault-lab_default -e PGPASSWORD="$DB_PASS" postgres:17 \
  psql -h postgres -U "$DB_USER" -d nettbutikk -c "SELECT current_user, now();"
```

* Innlogging kl 15:11:59 virket
* Samme innlogging kl 15:13:37 avvist med `password authentication failed`
* PostgreSQL gir samme feil uansett om brukeren finnes, noe som hindrer kartlegging av brukernavn

## Git

* Feil: `git add` stoppet helt fordi én av filene ikke fantes
* Sjekket med `git status` at `.env` aldri ble med i en commit
