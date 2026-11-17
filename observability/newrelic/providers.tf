provider "aws" {
  region = "us-east-1"
}

# User key (NEW_RELIC_API_KEY), não a license key de ingestão.
provider "newrelic" {
  account_id = var.newrelic_account_id
  api_key    = var.newrelic_api_key
  region     = "US"
}
