# Nettbutikken får bare lese sine egne hemmeligheter
path "secret/data/nettbutikk/*" {
  capabilities = ["read"]
}
