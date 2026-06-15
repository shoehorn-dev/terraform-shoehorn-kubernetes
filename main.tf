# =============================================================================
# Shoehorn Kubernetes Module
#
# Deploys Shoehorn, the Intelligent Developer Platform, to any Kubernetes cluster.
#
# Phase 1 (always): Helm release + health gate
# Phase 2 (deploy_agent = true): K8s agent token + agent Helm release
# =============================================================================

locals {
  secret_name     = "${var.release_name}-credentials"
  agent_name      = coalesce(var.cluster_name, var.cluster_id, "default")
  health_url      = "${var.health_check_protocol}://${var.domain}/healthz"
  org_name        = coalesce(var.organization_name, var.domain)
  use_external_db = var.database_host != ""
  pg_host         = local.use_external_db ? var.database_host : "${var.release_name}-postgresql.${var.namespace}.svc.cluster.local"
  pg_port         = local.use_external_db ? var.database_port : 5432
  pg_sslmode      = local.use_external_db ? var.database_sslmode : "disable"

  # Compute org_slug with leading/trailing hyphen trimming (QA finding)
  raw_slug = coalesce(var.organization_slug, replace(lower(var.domain), "/[^a-z0-9]+/", "-"))
  org_slug = trimprefix(trimsuffix(local.raw_slug, "-"), "-")

  # Set of credential keys present (used to conditionally emit *SecretRef blocks)
  cred_keys = keys(var.credentials)

  # Bootstrap Job uses an explicit override if set, otherwise derives from image_tag.
  bootstrap_image = var.bootstrap_image != "" ? var.bootstrap_image : "shoehorned/shoehorn-api:${var.image_tag}"

  # ---------------------------------------------------------------------------
  # Per-component *SecretRef blocks — chart references each credential by
  # secretKeyRef (name + key). With secret.defaultName set, name can be
  # omitted; the chart helper falls back to the shared default secret.
  # ---------------------------------------------------------------------------

  postgresql_block = merge(
    { enabled = !local.use_external_db },
    local.use_external_db ? {
      external = {
        enabled = true
        host    = var.database_host
        port    = var.database_port
      }
    } : {},
    contains(local.cred_keys, "postgres_password") ? { superuserPasswordSecretRef = { key = "postgres_password" } } : {},
    contains(local.cred_keys, "db_password") ? { passwordSecretRef = { key = "db_password" } } : {},
  )

  valkey_block = contains(local.cred_keys, "valkey_password") ? {
    passwordSecretRef = { key = "valkey_password" }
  } : {}

  meilisearch_block = contains(local.cred_keys, "meilisearch_master_key") ? {
    masterKeySecretRef = { key = "meilisearch_master_key" }
  } : {}

  # Auth session: jwt + encryption keys (required by chart for all providers)
  auth_session_block = merge(
    contains(local.cred_keys, "jwt_secret") ? { jwtSecretRef = { key = "jwt_secret" } } : {},
    contains(local.cred_keys, "auth_encryption_key") ? { encryptionKeyRef = { key = "auth_encryption_key" } } : {},
    contains(local.cred_keys, "session_encryption_key") ? { secretsEncryptionKeyRef = { key = "session_encryption_key" } } : {},
  )

  # Auth provider-specific block: non-secret fields from auth_config + credential refs
  okta_block = var.auth_provider == "okta" ? merge(
    var.auth_config,
    contains(local.cred_keys, "okta_client_secret") ? { clientSecretRef = { key = "okta_client_secret" } } : {},
    contains(local.cred_keys, "okta_api_token") ? { apiTokenSecretRef = { key = "okta_api_token" } } : {},
  ) : null

  zitadel_block = var.auth_provider == "zitadel" ? merge(
    var.auth_config,
    contains(local.cred_keys, "zitadel_service_user_pat") ? { serviceUserPatSecretRef = { key = "zitadel_service_user_pat" } } : {},
  ) : null

  entra_block = var.auth_provider == "entra-id" ? merge(
    var.auth_config,
    contains(local.cred_keys, "entra_client_secret") ? { clientSecretRef = { key = "entra_client_secret" } } : {},
  ) : null

  auth_block = merge(
    { provider = var.auth_provider },
    length(local.auth_session_block) > 0 ? { session = local.auth_session_block } : {},
    local.okta_block != null ? { okta = local.okta_block } : {},
    local.zitadel_block != null ? { zitadel = local.zitadel_block } : {},
    local.entra_block != null ? { entraId = local.entra_block } : {},
  )

  # ---------------------------------------------------------------------------
  # Top-level Helm values (rendered to YAML)
  # ---------------------------------------------------------------------------
  shoehorn_values = yamlencode({
    global = {
      domain       = var.domain
      storageClass = var.storage_class
      organization = {
        slug = local.org_slug
        name = local.org_name
      }
    }

    image = var.image_tag != null ? { tag = var.image_tag } : {}

    replicaCount = {
      api      = var.replica_count
      web      = var.replica_count
      eventbus = var.replica_count
      worker   = var.replica_count
      crawler  = var.replica_count
      forge    = var.replica_count
    }

    # Shared credentials Secret (this module creates the K8s Secret;
    # per-credential *SecretRef blocks below reference it by key only).
    secret = {
      defaultName = local.secret_name
    }

    postgresql  = local.postgresql_block
    valkey      = local.valkey_block
    meilisearch = local.meilisearch_block
    auth        = local.auth_block

    # RBAC admin bootstrap
    rbac = var.admin_email != "" ? {
      roleAssignment = {
        tenantAdmin = { user = var.admin_email }
      }
    } : {}

    # Ingress
    ingressRoute = { enabled = var.ingress_type == "ingressRoute" }
    ingress = merge(
      { enabled = var.ingress_type == "ingress" },
      var.ingress_class != "" ? { className = var.ingress_class } : {}
    )
    httpRoute = { enabled = var.ingress_type == "httpRoute" }

    # cert-manager subchart override: parent's global.logLevel ("info") would
    # propagate to cert-manager which expects a number — pin a number here.
    "cert-manager" = {
      global = {
        logLevel = 2
      }
    }
  })
}

# =============================================================================
# 1. Namespace
# =============================================================================

resource "kubernetes_namespace_v1" "shoehorn" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "shoehorn"
    }
  }
}

# =============================================================================
# 2. Credentials Secret
# =============================================================================

resource "kubernetes_secret_v1" "credentials" {
  metadata {
    name      = local.secret_name
    namespace = kubernetes_namespace_v1.shoehorn.metadata[0].name

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "shoehorn"
    }
  }

  data = var.credentials
}

# =============================================================================
# 3. Shoehorn Helm Release
# =============================================================================

resource "helm_release" "shoehorn" {
  name             = var.release_name
  repository       = var.chart_path != "" ? "" : var.chart_repository
  chart            = var.chart_path != "" ? var.chart_path : "shoehorn"
  version          = var.chart_version
  namespace        = kubernetes_namespace_v1.shoehorn.metadata[0].name
  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  timeout          = var.helm_timeout

  # Module-generated values (lowest priority)
  # then user YAML overrides
  # then user set overrides (highest priority)
  values = concat(
    [local.shoehorn_values],
    var.helm_values,
  )

  set = [for k, v in var.helm_set : { name = k, value = v }]

  set_sensitive = [for k, v in var.helm_set_sensitive : { name = k, value = v }]
}

# =============================================================================
# 4. Health Gate
# =============================================================================

data "http" "health" {
  url      = local.health_url
  insecure = true

  retry {
    attempts     = var.health_check_attempts
    min_delay_ms = 3000
    max_delay_ms = 10000
  }

  depends_on = [helm_release.shoehorn]
}

# =============================================================================
# 5. Bootstrap API Key Job (optional — for single-apply agent deployment)
# =============================================================================
# Seeds a deterministic API key derived from JWT_SECRET into the database
# so the Shoehorn provider can authenticate for agent registration in the
# same terraform apply. The key is derived identically on both sides
# (Go: DeriveBootstrapKey, Terraform: Python HMAC-SHA256).
#
# Depends on helm_release (not health_check) because it only needs
# PostgreSQL + migrations to have run, not a routable HTTPS endpoint.

resource "kubernetes_job_v1" "bootstrap_api_key" {
  count = var.enable_bootstrap && var.deploy_agent ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.bootstrap_image != "" || var.image_tag != null
      error_message = "Bootstrap requires either bootstrap_image or image_tag to be set. There is no \"latest\" tag."
    }
  }

  metadata {
    name      = "${var.release_name}-bootstrap-api-key"
    namespace = kubernetes_namespace_v1.shoehorn.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "shoehorn-bootstrap"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "shoehorn"
    }
  }

  spec {
    ttl_seconds_after_finished = 300
    active_deadline_seconds    = 300
    backoff_limit              = 3

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"       = "shoehorn-bootstrap"
          "app.kubernetes.io/managed-by" = "terraform"
        }
      }
      spec {
        restart_policy = "OnFailure"

        # Pull secrets for both the bootstrap container and the wait-for-db
        # init container. The chart's registryCredentials helper creates
        # Secrets named <release>-registry-<name>; callers pass them in via
        # var.image_pull_secrets (same list used by the agent helm release).
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secrets
          content {
            name = image_pull_secrets.value.name
          }
        }

        # Wait for PostgreSQL to accept queries. Reuses the chart's pinned
        # postgres image (already pulled by the StatefulSet) so this Job
        # doesn't need access to Docker Hub.
        init_container {
          name  = "wait-for-db"
          image = var.bootstrap_wait_db_image
          command = [
            "sh", "-c",
            "until pg_isready -h ${local.pg_host} -p ${local.pg_port}; do echo waiting for postgresql; sleep 2; done"
          ]
          security_context {
            run_as_non_root            = true
            run_as_user                = 65534
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
          }
        }

        container {
          name    = "bootstrap"
          image   = local.bootstrap_image
          command = ["/api", "--bootstrap-api-key"]

          # MIGRATION_DATABASE_URL built at runtime via shell to avoid
          # password appearing in pod spec (C1 security finding).
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.secret_name
                key  = "postgres_password"
              }
            }
          }

          env {
            name  = "DB_HOST"
            value = local.pg_host
          }

          env {
            name  = "DB_PORT"
            value = tostring(local.pg_port)
          }

          env {
            name  = "DB_SSLMODE"
            value = local.pg_sslmode
          }

          env {
            name = "APP_USER_PASSWORD"
            value_from {
              secret_key_ref {
                name = local.secret_name
                key  = "db_password"
              }
            }
          }

          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = local.secret_name
                key  = "jwt_secret"
              }
            }
          }

          env {
            name  = "ENVIRONMENT"
            value = var.bootstrap_environment
          }

          env {
            name  = "BOOTSTRAP_ORG_SLUG"
            value = local.org_slug
          }

          env {
            name  = "BOOTSTRAP_ORG_NAME"
            value = local.org_name
          }

          env {
            name  = "LOG_LEVEL"
            value = "info"
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 65534
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }

  depends_on = [helm_release.shoehorn]
}

# =============================================================================
# 6. K8s Agent Registration (Phase 2)
# =============================================================================

resource "shoehorn_k8s_agent" "cluster" {
  count = var.deploy_agent ? 1 : 0

  name       = local.agent_name
  cluster_id = var.cluster_id

  depends_on = [data.http.health, kubernetes_job_v1.bootstrap_api_key]
}

# =============================================================================
# 7. K8s Agent Helm Release (Phase 2)
# =============================================================================

resource "helm_release" "k8s_agent" {
  count = var.deploy_agent ? 1 : 0

  name             = "${var.release_name}-k8s-agent"
  repository       = var.agent_chart_path != "" ? "" : var.chart_repository
  chart            = var.agent_chart_path != "" ? var.agent_chart_path : "shoehorn-k8s-agent"
  version          = var.agent_chart_version
  namespace        = kubernetes_namespace_v1.shoehorn.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 300

  values = concat(
    [yamlencode({
      shoehorn = {
        apiURL = "${var.health_check_protocol}://${var.domain}"
        cluster = {
          id   = var.cluster_id
          name = local.agent_name
        }
      }
      image = var.agent_image_tag != null ? {
        tag        = var.agent_image_tag
        pullPolicy = "Always"
      } : {}
      imagePullSecrets = var.image_pull_secrets
      agent = merge(
        var.agent_gitops_tool != "" ? {
          gitops = merge(
            { tool = var.agent_gitops_tool },
            var.agent_gitops_tool == "argocd" ? {
              argocd = {
                namespace = var.argocd_namespace
                serverURL = var.argocd_server_url
              }
            } : {},
          )
        } : {},
        var.agent_helm_enabled ? {
          helm = {
            enabled   = true
            namespace = var.agent_helm_namespace
            interval  = var.agent_helm_interval
          }
        } : {},
        var.agent_connected_enabled ? {
          connected = {
            enabled = true
          }
        } : {},
      )
    })],
    var.agent_helm_values,
  )

  set_sensitive = concat(
    [{ name = "shoehorn.apiToken", value = shoehorn_k8s_agent.cluster[0].token }],
    var.agent_gitops_tool == "argocd" && var.argocd_token != "" ? [
      { name = "agent.gitops.argocd.token", value = var.argocd_token },
    ] : [],
  )

  set = [for k, v in var.agent_helm_set : { name = k, value = v }]
}
