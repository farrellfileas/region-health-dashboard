terraform {
    backend "s3" {
        bucket                      = "region-health-tfstate"
        key                         = "oke/terraform.tfstate"
        region                      = "us-phoenix-1"
        endpoints = {
            s3 = "https://axhcuwsuvvsi.compat.objectstorage.us-phoenix-1.oraclecloud.com"
        }
        shared_credentials_file     = "~/.oci/credentials"
        skip_region_validation      = true
        skip_credentials_validation = true
        skip_metadata_api_check     = true
        force_path_style            = true
        skip_requesting_account_id  = true
    }
}