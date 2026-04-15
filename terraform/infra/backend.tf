terraform {
    # Local for simplicity
  backend "local" {
    path = "terraform.tfstate"
  }
}