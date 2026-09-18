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

run "unset_leaves_mcp_login_to_the_chart" {
  command = plan

  assert {
    condition     = !contains(keys(yamldecode(helm_release.shoehorn.values[0]).auth.mcp), "enabled")
    error_message = "auth.mcp.enabled must be absent when mcp_oauth_enabled is unset, so the chart default (on) applies"
  }
}

run "explicit_false_turns_it_off" {
  command = plan

  variables {
    mcp_oauth_enabled = false
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.mcp.enabled == false
    error_message = "an explicit false must reach the chart"
  }
}

run "explicit_true_is_passed_through" {
  command = plan

  variables {
    mcp_oauth_enabled = true
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.mcp.enabled == true
    error_message = "an explicit true must reach the chart"
  }
}

run "other_mcp_settings_still_render" {
  command = plan

  variables {
    mcp_oauth_client_id = "shoehorn-mcp"
  }

  assert {
    condition     = yamldecode(helm_release.shoehorn.values[0]).auth.mcp.clientId == "shoehorn-mcp"
    error_message = "clientId must still be rendered when enabled is left to the chart"
  }
}

run "bootstrap_without_a_tag_stops_at_the_precondition" {
  command = plan

  variables {
    enable_bootstrap = true
    deploy_agent     = true
  }

  expect_failures = [kubernetes_job_v1.bootstrap_api_key]
}
