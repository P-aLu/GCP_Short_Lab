terraform {
  backend "gcs" {
    # bucket and prefix are injected by lab.sh:
    #   -backend-config="bucket=<STATE_BUCKET>"
    #   -backend-config="prefix=lab-01-gsc-privesc"
  }
}
