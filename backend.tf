terraform {
  backend "gcs" {
    bucket = "project-899ced78-a554-40c2-96c-tfstate"
    prefix = "global"
  }
}
