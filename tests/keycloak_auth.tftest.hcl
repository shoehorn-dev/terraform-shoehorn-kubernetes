mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "http" {}
mock_provider "shoehorn" {}

variables {
  domain = "shoehorn.example.com"
  credentials = {
    postgres_password      = "test"
    db_password            = "test"
    jwt_secret             = "test"
    auth_encryption_key    = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
    session_encryption_key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
  }
}

run "keycloak_is_accepted_as_auth_provider" {
  command = plan

  variables {
    auth_provider = "keycloak"
    auth_audience = "shoehorn-web"
    auth_config = {
      url      = "https://keycloak.example.com"
      realm    = "shoehorn"
      clientId = "shoehorn-web"
    }
    credentials = {
      postgres_password      = "test"
      db_password             = "test"
      jwt_secret              = "test"
      auth_encryption_key     = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
      session_encryption_key  = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
      keycloak_client_secret  = "test-login-secret"
    }
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.provider == "keycloak"
    error_message = "auth.provider must be keycloak"
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.audience == "shoehorn-web"
    error_message = "auth.audience must reach the chart - Keycloak does not auto-derive it the way Okta does"
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.keycloak.url == "https://keycloak.example.com"
    error_message = "auth.keycloak.url must be set from auth_config"
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.keycloak.clientSecretRef.key == "keycloak_client_secret"
    error_message = "clientSecretRef must be wired from the credentials map, matching the okta_client_secret convention"
  }
}

run "keycloak_admin_secret_is_wired_when_present" {
  command = plan

  variables {
    auth_provider = "keycloak"
    auth_audience = "shoehorn-web"
    auth_config = {
      url      = "https://keycloak.example.com"
      realm    = "shoehorn"
      clientId = "shoehorn-web"
    }
    credentials = {
      postgres_password            = "test"
      db_password                  = "test"
      jwt_secret                   = "test"
      auth_encryption_key          = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
      session_encryption_key       = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q="
      keycloak_client_secret       = "test-login-secret"
      keycloak_admin_client_secret = "test-admin-secret"
    }
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.keycloak.adminClientSecretRef.key == "keycloak_admin_client_secret"
    error_message = "adminClientSecretRef must be wired from the credentials map when present"
  }
}

run "keycloak_missing_required_auth_config_keys_fails_plan" {
  command = plan

  variables {
    auth_provider = "keycloak"
    auth_config   = {}
  }

  expect_failures = [helm_release.shoehorn]
}

run "a_different_provider_emits_no_keycloak_block" {
  command = plan

  variables {
    auth_provider = "zitadel"
    auth_config = {
      clientId    = "1"
      projectId   = "2"
      externalUrl = "https://auth.example.com"
    }
  }

  assert {
    condition     = !contains(keys(yamldecode(helm_release.shoehorn.values[0]).auth), "keycloak")
    error_message = "auth.keycloak must be absent when auth_provider is not keycloak"
  }
}
