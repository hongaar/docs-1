gcloud privateca certificates create \
  --issuer-pool roach-test-client-ca3-pool \
  --generate-key \
  --extended-key-usages "client_auth" \
  --key-output-file client.root.key \
  --cert-output-file client.root.crt \
  --subject "CN=root"