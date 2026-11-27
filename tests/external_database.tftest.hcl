mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "http" {}
mock_provider "shoehorn" {}

variables {
  domain = "shoehorn.example.com"
  auth_config = {
    clientId    = "test-client-id"
    projectId   = "test-project-id"
    externalUrl = "https://auth.example.com"
  }
  credentials = {
    postgres_password      = "test"
    db_password            = "test"
    jwt_secret             = "test"
    auth_encryption_key    = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
    session_encryption_key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
  }
}

# database_name, database_user and database_sslmode were declared and
# documented but never reached the chart: an external database got the chart's
# default name and user, and sslmode=disable (2026-11-27 parity audit, 5g).
run "external_database_settings_reach_the_chart" {
  command = plan

  variables {
    database_host    = "db.example.com"
    database_port    = 6543
    database_name    = "idp"
    database_user    = "idp_owner"
    database_sslmode = "verify-full"
  }

  assert {
    condition = alltrue([
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.external.enabled) == true,
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.external.host) == "db.example.com",
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.external.port) == 6543,
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.external.database) == "idp",
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.external.user) == "idp_owner",
    ])
    error_message = "postgresql.external must carry host, port, database and user"
  }

  assert {
    condition = alltrue([
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.tls.enabled) == true,
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.tls.sslMode) == "verify-full",
      nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.tls.createCertificate) == false,
    ])
    error_message = "database_sslmode must turn on postgresql.tls with that sslMode, without a bundled certificate"
  }
}

run "external_database_without_tls" {
  command = plan

  variables {
    database_host    = "db.example.com"
    database_sslmode = "disable"
  }

  assert {
    condition     = nonsensitive(yamldecode(helm_release.shoehorn.values[0]).postgresql.tls.enabled) == false
    error_message = "database_sslmode = \"disable\" must leave postgresql.tls off"
  }
}

run "bundled_database_leaves_tls_to_the_chart" {
  command = plan

  assert {
    condition     = !contains(nonsensitive(keys(yamldecode(helm_release.shoehorn.values[0]).postgresql)), "tls")
    error_message = "the bundled database must not get a postgresql.tls block from the module"
  }
}

# The eventbus service is gone in 0.7.0; the chart no longer reads its values.
run "no_eventbus_values" {
  command = plan

  assert {
    condition     = !contains(nonsensitive(keys(yamldecode(helm_release.shoehorn.values[0]).replicaCount)), "eventbus")
    error_message = "replicaCount.eventbus is no longer a chart value"
  }
}
