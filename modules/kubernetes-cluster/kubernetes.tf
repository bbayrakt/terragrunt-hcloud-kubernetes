module "kubernetes" {
  source  = "hcloud-k8s/kubernetes/hcloud"
  version = var.terraform_hcloud_kubernetes_module_version

  cluster_name            = var.cluster_name
  control_plane_nodepools = var.control_plane_nodepools
  hcloud_token            = var.hcloud_token

  # Only non-default values are passed through
  # All other variables will use module defaults

  # Cert Manager
  cert_manager_enabled       = var.cert_manager_enabled
  cert_manager_helm_chart    = var.cert_manager_helm_chart
  cert_manager_helm_repository = var.cert_manager_helm_repository
  cert_manager_helm_values   = var.cert_manager_helm_values
  cert_manager_helm_version  = var.cert_manager_helm_version

  # Cilium
  cilium_bpf_datapath_mode                      = var.cilium_bpf_datapath_mode
  cilium_egress_gateway_enabled                 = var.cilium_egress_gateway_enabled
  cilium_enabled                                = var.cilium_enabled
  cilium_encryption_enabled                     = var.cilium_encryption_enabled
  cilium_encryption_type                        = var.cilium_encryption_type
  cilium_gateway_api_enabled                    = var.cilium_gateway_api_enabled
  cilium_gateway_api_external_traffic_policy    = var.cilium_gateway_api_external_traffic_policy
  cilium_gateway_api_proxy_protocol_enabled     = var.cilium_gateway_api_proxy_protocol_enabled
  cilium_helm_chart                             = var.cilium_helm_chart
  cilium_helm_repository                        = var.cilium_helm_repository
  cilium_helm_values                            = var.cilium_helm_values
  cilium_helm_version                           = var.cilium_helm_version
  cilium_hubble_enabled                         = var.cilium_hubble_enabled
  cilium_hubble_relay_enabled                   = var.cilium_hubble_relay_enabled
  cilium_hubble_ui_enabled                      = var.cilium_hubble_ui_enabled
  cilium_ipsec_algorithm                        = var.cilium_ipsec_algorithm
  cilium_ipsec_key_id                           = var.cilium_ipsec_key_id
  cilium_ipsec_key_size                         = var.cilium_ipsec_key_size
  cilium_kube_proxy_replacement_enabled         = var.cilium_kube_proxy_replacement_enabled
  cilium_load_balancer_acceleration             = var.cilium_load_balancer_acceleration
  cilium_policy_cidr_match_mode                 = var.cilium_policy_cidr_match_mode
  cilium_routing_mode                           = var.cilium_routing_mode
  cilium_service_monitor_enabled                = var.cilium_service_monitor_enabled
  cilium_socket_lb_host_namespace_only_enabled  = var.cilium_socket_lb_host_namespace_only_enabled

  # Client and Cluster Settings
  client_prerequisites_check_enabled        = var.client_prerequisites_check_enabled
  cluster_access                            = var.cluster_access
  cluster_allow_scheduling_on_control_planes = var.cluster_allow_scheduling_on_control_planes
  cluster_delete_protection                 = var.cluster_delete_protection
  cluster_domain                            = var.cluster_domain
  cluster_graceful_destroy                  = var.cluster_graceful_destroy
  cluster_healthcheck_enabled               = var.cluster_healthcheck_enabled
  cluster_kubeconfig_path                   = var.cluster_kubeconfig_path
  cluster_rdns                              = var.cluster_rdns
  cluster_rdns_ipv4                         = var.cluster_rdns_ipv4
  cluster_rdns_ipv6                         = var.cluster_rdns_ipv6
  cluster_talosconfig_path                  = var.cluster_talosconfig_path

  # Cluster Autoscaler
  cluster_autoscaler_config_patches       = var.cluster_autoscaler_config_patches
  cluster_autoscaler_discovery_enabled    = var.cluster_autoscaler_discovery_enabled
  cluster_autoscaler_helm_chart           = var.cluster_autoscaler_helm_chart
  cluster_autoscaler_helm_repository      = var.cluster_autoscaler_helm_repository
  cluster_autoscaler_helm_values          = var.cluster_autoscaler_helm_values
  cluster_autoscaler_helm_version         = var.cluster_autoscaler_helm_version
  cluster_autoscaler_image_tag            = var.cluster_autoscaler_image_tag
  cluster_autoscaler_nodepools            = var.cluster_autoscaler_nodepools

  # Control Plane
  control_plane_config_patches          = var.control_plane_config_patches
  control_plane_private_vip_ipv4_enabled = var.control_plane_private_vip_ipv4_enabled
  control_plane_public_vip_ipv4_enabled = var.control_plane_public_vip_ipv4_enabled
  control_plane_public_vip_ipv4_id      = var.control_plane_public_vip_ipv4_id

  # Firewall
  firewall_api_source           = var.firewall_api_source
  firewall_extra_rules          = var.firewall_extra_rules
  firewall_id                   = var.firewall_id
  firewall_kube_api_source      = var.firewall_kube_api_source
  firewall_talos_api_source     = var.firewall_talos_api_source
  firewall_use_current_ipv4     = var.firewall_use_current_ipv4
  firewall_use_current_ipv6     = var.firewall_use_current_ipv6

  # Gateway API
  gateway_api_crds_enabled         = var.gateway_api_crds_enabled
  gateway_api_crds_release_channel = var.gateway_api_crds_release_channel
  gateway_api_crds_version         = var.gateway_api_crds_version

  # Hetzner Cloud CCM
  hcloud_ccm_enabled                                = var.hcloud_ccm_enabled
  hcloud_ccm_helm_chart                             = var.hcloud_ccm_helm_chart
  hcloud_ccm_helm_repository                        = var.hcloud_ccm_helm_repository
  hcloud_ccm_helm_values                            = var.hcloud_ccm_helm_values
  hcloud_ccm_helm_version                           = var.hcloud_ccm_helm_version
  hcloud_ccm_load_balancers_algorithm_type          = var.hcloud_ccm_load_balancers_algorithm_type
  hcloud_ccm_load_balancers_disable_ipv6            = var.hcloud_ccm_load_balancers_disable_ipv6
  hcloud_ccm_load_balancers_disable_private_ingress = var.hcloud_ccm_load_balancers_disable_private_ingress
  hcloud_ccm_load_balancers_disable_public_network  = var.hcloud_ccm_load_balancers_disable_public_network
  hcloud_ccm_load_balancers_enabled                 = var.hcloud_ccm_load_balancers_enabled
  hcloud_ccm_load_balancers_health_check_interval   = var.hcloud_ccm_load_balancers_health_check_interval
  hcloud_ccm_load_balancers_health_check_retries    = var.hcloud_ccm_load_balancers_health_check_retries
  hcloud_ccm_load_balancers_health_check_timeout    = var.hcloud_ccm_load_balancers_health_check_timeout
  hcloud_ccm_load_balancers_location                = var.hcloud_ccm_load_balancers_location
  hcloud_ccm_load_balancers_type                    = var.hcloud_ccm_load_balancers_type
  hcloud_ccm_load_balancers_use_private_ip          = var.hcloud_ccm_load_balancers_use_private_ip
  hcloud_ccm_load_balancers_uses_proxyprotocol      = var.hcloud_ccm_load_balancers_uses_proxyprotocol
  hcloud_ccm_network_routes_enabled                 = var.hcloud_ccm_network_routes_enabled

  # Hetzner Cloud CSI
  hcloud_csi_enabled               = var.hcloud_csi_enabled
  hcloud_csi_encryption_passphrase = var.hcloud_csi_encryption_passphrase
  hcloud_csi_helm_chart            = var.hcloud_csi_helm_chart
  hcloud_csi_helm_repository       = var.hcloud_csi_helm_repository
  hcloud_csi_helm_values           = var.hcloud_csi_helm_values
  hcloud_csi_helm_version          = var.hcloud_csi_helm_version
  hcloud_csi_storage_classes       = var.hcloud_csi_storage_classes
  hcloud_csi_volume_extra_labels   = var.hcloud_csi_volume_extra_labels

  # Hetzner Network
  hcloud_network    = var.hcloud_network
  hcloud_network_id = var.hcloud_network_id

  # Ingress Load Balancer
  ingress_load_balancer_algorithm              = var.ingress_load_balancer_algorithm
  ingress_load_balancer_health_check_interval  = var.ingress_load_balancer_health_check_interval
  ingress_load_balancer_health_check_retries   = var.ingress_load_balancer_health_check_retries
  ingress_load_balancer_health_check_timeout   = var.ingress_load_balancer_health_check_timeout
  ingress_load_balancer_pools                  = var.ingress_load_balancer_pools
  ingress_load_balancer_public_network_enabled = var.ingress_load_balancer_public_network_enabled
  ingress_load_balancer_rdns                   = var.ingress_load_balancer_rdns
  ingress_load_balancer_rdns_ipv4              = var.ingress_load_balancer_rdns_ipv4
  ingress_load_balancer_rdns_ipv6              = var.ingress_load_balancer_rdns_ipv6
  ingress_load_balancer_type                   = var.ingress_load_balancer_type

  # Ingress NGINX
  ingress_nginx_config                         = var.ingress_nginx_config
  ingress_nginx_enabled                        = var.ingress_nginx_enabled
  ingress_nginx_helm_chart                     = var.ingress_nginx_helm_chart
  ingress_nginx_helm_repository                = var.ingress_nginx_helm_repository
  ingress_nginx_helm_values                    = var.ingress_nginx_helm_values
  ingress_nginx_helm_version                   = var.ingress_nginx_helm_version
  ingress_nginx_kind                           = var.ingress_nginx_kind
  ingress_nginx_replicas                       = var.ingress_nginx_replicas
  ingress_nginx_service_external_traffic_policy = var.ingress_nginx_service_external_traffic_policy
  ingress_nginx_topology_aware_routing         = var.ingress_nginx_topology_aware_routing

  # Kubernetes API
  kube_api_admission_control                   = var.kube_api_admission_control
  kube_api_extra_args                          = var.kube_api_extra_args
  kube_api_hostname                            = var.kube_api_hostname
  kube_api_load_balancer_enabled               = var.kube_api_load_balancer_enabled
  kube_api_load_balancer_public_network_enabled = var.kube_api_load_balancer_public_network_enabled

  # Kubernetes
  kubernetes_kubelet_extra_args   = var.kubernetes_kubelet_extra_args
  kubernetes_kubelet_extra_config = var.kubernetes_kubelet_extra_config
  kubernetes_version              = var.kubernetes_version

  # Longhorn
  longhorn_default_storage_class = var.longhorn_default_storage_class
  longhorn_enabled               = var.longhorn_enabled
  longhorn_helm_chart            = var.longhorn_helm_chart
  longhorn_helm_repository       = var.longhorn_helm_repository
  longhorn_helm_values           = var.longhorn_helm_values
  longhorn_helm_version          = var.longhorn_helm_version

  # Metrics Server
  metrics_server_enabled                  = var.metrics_server_enabled
  metrics_server_helm_chart               = var.metrics_server_helm_chart
  metrics_server_helm_repository          = var.metrics_server_helm_repository
  metrics_server_helm_values              = var.metrics_server_helm_values
  metrics_server_helm_version             = var.metrics_server_helm_version
  metrics_server_replicas                 = var.metrics_server_replicas
  metrics_server_schedule_on_control_plane = var.metrics_server_schedule_on_control_plane

  # Network
  network_ipv4_cidr                 = var.network_ipv4_cidr
  network_native_routing_ipv4_cidr  = var.network_native_routing_ipv4_cidr
  network_node_ipv4_cidr            = var.network_node_ipv4_cidr
  network_node_ipv4_subnet_mask_size = var.network_node_ipv4_subnet_mask_size
  network_pod_ipv4_cidr             = var.network_pod_ipv4_cidr
  network_service_ipv4_cidr         = var.network_service_ipv4_cidr

  # OIDC
  oidc_client_id       = var.oidc_client_id
  oidc_enabled         = var.oidc_enabled
  oidc_group_mappings  = var.oidc_group_mappings
  oidc_groups_claim    = var.oidc_groups_claim
  oidc_groups_prefix   = var.oidc_groups_prefix
  oidc_issuer_url      = var.oidc_issuer_url
  oidc_username_claim  = var.oidc_username_claim

  # Packer
  packer_amd64_builder = var.packer_amd64_builder
  packer_arm64_builder = var.packer_arm64_builder

  # Prometheus
  prometheus_operator_crds_enabled = var.prometheus_operator_crds_enabled
  prometheus_operator_crds_version = var.prometheus_operator_crds_version

  # RBAC
  rbac_cluster_roles = var.rbac_cluster_roles
  rbac_roles         = var.rbac_roles

  # Talos Backup
  talos_backup_age_x25519_public_key = var.talos_backup_age_x25519_public_key
  talos_backup_enable_compression    = var.talos_backup_enable_compression
  talos_backup_s3_access_key         = var.talos_backup_s3_access_key
  talos_backup_s3_bucket             = var.talos_backup_s3_bucket
  talos_backup_s3_enabled            = var.talos_backup_s3_enabled
  talos_backup_s3_endpoint           = var.talos_backup_s3_endpoint
  talos_backup_s3_hcloud_url         = var.talos_backup_s3_hcloud_url
  talos_backup_s3_path_style         = var.talos_backup_s3_path_style
  talos_backup_s3_prefix             = var.talos_backup_s3_prefix
  talos_backup_s3_region             = var.talos_backup_s3_region
  talos_backup_s3_secret_key         = var.talos_backup_s3_secret_key
  talos_backup_schedule              = var.talos_backup_schedule
  talos_backup_version               = var.talos_backup_version

  # Talos
  talos_ccm_enabled                            = var.talos_ccm_enabled
  talos_ccm_version                            = var.talos_ccm_version
  talos_coredns_enabled                        = var.talos_coredns_enabled
  talos_discovery_kubernetes_enabled           = var.talos_discovery_kubernetes_enabled
  talos_discovery_service_enabled              = var.talos_discovery_service_enabled
  talos_ephemeral_partition_encryption_enabled = var.talos_ephemeral_partition_encryption_enabled
  talos_extra_host_entries                     = var.talos_extra_host_entries
  talos_extra_inline_manifests                 = var.talos_extra_inline_manifests
  talos_extra_kernel_args                      = var.talos_extra_kernel_args
  talos_extra_remote_manifests                 = var.talos_extra_remote_manifests
  talos_extra_routes                           = var.talos_extra_routes
  talos_image_extensions                       = var.talos_image_extensions
  talos_ipv6_enabled                           = var.talos_ipv6_enabled
  talos_kernel_modules                         = var.talos_kernel_modules
  talos_kubelet_extra_mounts                   = var.talos_kubelet_extra_mounts
  talos_logging_destinations                   = var.talos_logging_destinations
  talos_machine_configuration_apply_mode       = var.talos_machine_configuration_apply_mode
  talos_nameservers                            = var.talos_nameservers
  talos_public_ipv4_enabled                    = var.talos_public_ipv4_enabled
  talos_public_ipv6_enabled                    = var.talos_public_ipv6_enabled
  talos_registries                             = var.talos_registries
  talos_schematic_id                           = var.talos_schematic_id
  talos_state_partition_encryption_enabled     = var.talos_state_partition_encryption_enabled
  talos_sysctls_extra_args                     = var.talos_sysctls_extra_args
  talos_time_servers                           = var.talos_time_servers
  talos_upgrade_debug                          = var.talos_upgrade_debug
  talos_upgrade_force                          = var.talos_upgrade_force
  talos_upgrade_insecure                       = var.talos_upgrade_insecure
  talos_upgrade_reboot_mode                    = var.talos_upgrade_reboot_mode
  talos_upgrade_stage                          = var.talos_upgrade_stage
  talos_version                                = var.talos_version

  # Talosctl
  talosctl_retries                = var.talosctl_retries
  talosctl_version_check_enabled  = var.talosctl_version_check_enabled

  # Workers
  worker_config_patches = var.worker_config_patches
  worker_nodepools      = var.worker_nodepools
}
