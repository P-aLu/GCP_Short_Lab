terraform {
  backend "gcs" {
    # bucket and prefix injected by lab.sh / deploy-chain.sh:
    #   -backend-config="bucket=<STATE_BUCKET>"
    #   -backend-config="prefix=lab-03-admin-takeover"
  }
}
