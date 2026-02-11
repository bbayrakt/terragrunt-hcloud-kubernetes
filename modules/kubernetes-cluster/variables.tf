variable "terraform_hcloud_kubernetes_module_version" {
  description = "Version of the hcloud-k8s Kubernetes module to use"
  type        = string
}

variable "cluster_name" {
  description = "Specifies the name of the cluster. This name is used to identify the cluster within the infrastructure and should be unique across all deployments"
  type        = string
}

variable "control_plane_nodepools" {
  description = "Configures the number and attributes of Control Plane nodes"
  type = list(object({
    name        = string
    location    = string
    type        = string
    backups     = optional(bool, false)
    keep_disk   = optional(bool, false)
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
    taints      = optional(list(string), [])
    count       = optional(number, 1)
    rdns        = optional(string)
    rdns_ipv4   = optional(string)
    rdns_ipv6   = optional(string)
  }))
}

variable "hcloud_token" {
  description = "The Hetzner Cloud API token used for authentication with Hetzner Cloud services. This token should be treated as sensitive information"
  type        = string
  sensitive   = true
}

variable "cert_manager_enabled" {
  description = "Enables the deployment of cert-manager for managing TLS certificates"
  type        = bool
  default     = false
}

variable "cert_manager_helm_chart" {
  description = "Name of the Helm chart used for deploying Cert Manager"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_helm_repository" {
  description = "URL of the Helm repository where the Cert Manager chart is located"
  type        = string
  default     = "https://charts.jetstack.io"
}

variable "cert_manager_helm_values" {
  description = "Custom Helm values for the Cert Manager chart deployment. These values will merge with and will override the default values provided by the Cert Manager Helm chart"
  type        = any
  default     = {}
}

variable "cert_manager_helm_version" {
  description = "Version of the Cert Manager Helm chart to deploy"
  type        = string
  default     = "v1.19.3"
}

variable "cilium_bpf_datapath_mode" {
  description = "Mode for Pod devices for the core datapath. Allowed values: veth, netkit, netkit-l2. Warning: Netkit is still in beta and should not be used together with IPsec encryption!"
  type        = string
  default     = "veth"
}

variable "cilium_egress_gateway_enabled" {
  description = "Enables egress gateway to redirect and SNAT the traffic that leaves the cluster"
  type        = bool
  default     = false
}

variable "cilium_enabled" {
  description = "Enables the Cilium CNI deployment"
  type        = bool
  default     = true
}

variable "cilium_encryption_enabled" {
  description = "Enables transparent network encryption using Cilium within the Kubernetes cluster. When enabled, this feature provides added security for network traffic"
  type        = bool
  default     = true
}

variable "cilium_encryption_type" {
  description = "Type of encryption to use for Cilium network encryption. Options: 'wireguard' or 'ipsec'"
  type        = string
  default     = "wireguard"
}

variable "cilium_gateway_api_enabled" {
  description = "Enables Cilium Gateway API"
  type        = bool
  default     = false
}

variable "cilium_gateway_api_external_traffic_policy" {
  description = "Denotes if this Service desires to route external traffic to node-local or cluster-wide endpoints"
  type        = string
  default     = "Cluster"
}

variable "cilium_gateway_api_proxy_protocol_enabled" {
  description = "Enable PROXY Protocol on Cilium Gateway API for external load balancer traffic"
  type        = bool
  default     = true
}

variable "cilium_helm_chart" {
  description = "Name of the Helm chart used for deploying Cilium"
  type        = string
  default     = "cilium"
}

variable "cilium_helm_repository" {
  description = "URL of the Helm repository where the Cilium chart is located"
  type        = string
  default     = "https://helm.cilium.io"
}

variable "cilium_helm_values" {
  description = "Custom Helm values for the Cilium chart deployment. These values will merge with and will override the default values provided by the Cilium Helm chart"
  type        = any
  default     = {}
}

variable "cilium_helm_version" {
  description = "Version of the Cilium Helm chart to deploy"
  type        = string
  default     = "1.18.6"
}

variable "cilium_hubble_enabled" {
  description = "Enables Hubble observability within Cilium, which may impact performance with an overhead of 1-15% depending on network traffic patterns and settings"
  type        = bool
  default     = false
}

variable "cilium_hubble_relay_enabled" {
  description = "Enables Hubble Relay, which requires Hubble to be enabled"
  type        = bool
  default     = false
}

variable "cilium_hubble_ui_enabled" {
  description = "Enables the Hubble UI, which requires Hubble Relay to be enabled"
  type        = bool
  default     = false
}

variable "cilium_ipsec_algorithm" {
  description = "Cilium IPSec key algorithm"
  type        = string
  default     = "rfc4106(gcm(aes))"
}

variable "cilium_ipsec_key_id" {
  description = "IPSec key ID (1-15, increment manually for rotation). Only used when cilium_encryption_type is 'ipsec'"
  type        = number
  default     = 1
}

variable "cilium_ipsec_key_size" {
  description = "AES key size in bits for IPSec encryption (128, 192, or 256). Only used when cilium_encryption_type is 'ipsec'"
  type        = number
  default     = 256
}

variable "cilium_kube_proxy_replacement_enabled" {
  description = "Enables Cilium's eBPF kube-proxy replacement"
  type        = bool
  default     = true
}

variable "cilium_load_balancer_acceleration" {
  description = "Cilium XDP Acceleration mode"
  type        = string
  default     = "native"
}

variable "cilium_policy_cidr_match_mode" {
  description = "Allows setting policy-cidr-match-mode to 'nodes', which means that cluster nodes can be selected by CIDR network policies. Normally nodes are only accessible via remote-node entity selectors. This is required if you want to target the kube-api server with a k8s NetworkPolicy"
  type        = string
  default     = ""
}

variable "cilium_routing_mode" {
  description = "Cilium routing mode (e.g., 'native', 'tunnel', etc.)"
  type        = string
  default     = "native"
}

variable "cilium_service_monitor_enabled" {
  description = "Enables service monitors for Prometheus if set to true"
  type        = bool
  default     = false
}

variable "cilium_socket_lb_host_namespace_only_enabled" {
  description = "Limit Cilium's socket-level load-balancing to the host namespace only"
  type        = bool
  default     = false
}

variable "client_prerequisites_check_enabled" {
  description = "Controls whether a preflight check verifies that required client tools are installed before provisioning"
  type        = bool
  default     = true
}

variable "cluster_access" {
  description = "Defines how the cluster is accessed externally. Specifies if access should be through public or private IPs"
  type        = string
  default     = "public"
}

variable "cluster_allow_scheduling_on_control_planes" {
  description = "Allow scheduling on control plane nodes. If this is false, scheduling on control plane nodes is explicitly disabled. Defaults to true if there are no workers present"
  type        = bool
  default     = null
}

variable "cluster_autoscaler_config_patches" {
  description = "List of configuration patches applied to the Cluster Autoscaler nodes"
  type        = any
  default     = []
}

variable "cluster_autoscaler_discovery_enabled" {
  description = "Enable rolling upgrades of Cluster Autoscaler nodes during Talos OS upgrades and Talos configuration changes"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_helm_chart" {
  description = "Name of the Helm chart used for deploying Cluster Autoscaler"
  type        = string
  default     = "cluster-autoscaler"
}

variable "cluster_autoscaler_helm_repository" {
  description = "URL of the Helm repository where the Cluster Autoscaler chart is located"
  type        = string
  default     = "https://kubernetes.github.io/autoscaler"
}

variable "cluster_autoscaler_helm_values" {
  description = "Custom Helm values for the Cluster Autoscaler chart deployment. These values will merge with and will override the default values provided by the Cluster Autoscaler Helm chart"
  type        = any
  default     = {}
}

variable "cluster_autoscaler_helm_version" {
  description = "Version of the Cluster Autoscaler Helm chart to deploy"
  type        = string
  default     = "9.50.1"
}

variable "cluster_autoscaler_image_tag" {
  description = "Version of the Cluster Autoscaler Image"
  type        = string
  default     = "v1.33.4"
}

variable "cluster_autoscaler_nodepools" {
  description = "Defines configuration settings for Autoscaler node pools within the cluster"
  type = list(object({
    name        = string
    location    = string
    type        = string
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
    taints      = optional(list(string), [])
    min         = optional(number, 0)
    max         = number
  }))
  default = []
}

variable "cluster_delete_protection" {
  description = "Adds delete protection for resources that support it"
  type        = bool
  default     = true
}

variable "cluster_domain" {
  description = "Specifies the domain name used by the cluster. This domain name is integral for internal networking and service discovery within the cluster. The default is 'cluster.local', which is commonly used for local Kubernetes clusters"
  type        = string
  default     = "cluster.local"
}

variable "cluster_graceful_destroy" {
  description = "Determines whether a graceful destruction process is enabled for Talos nodes. When enabled, it ensures that nodes are properly drained and decommissioned before being destroyed, minimizing disruption in the cluster"
  type        = bool
  default     = true
}

variable "cluster_healthcheck_enabled" {
  description = "Determines whether are executed during cluster deployment and upgrade"
  type        = bool
  default     = true
}

variable "cluster_kubeconfig_path" {
  description = "If not null, the kubeconfig will be written to a file speficified"
  type        = string
  default     = null
}

variable "cluster_rdns" {
  description = "Specifies the general reverse DNS FQDN for the cluster, used for internal networking and service discovery. Supports dynamic substitution with placeholders: {{ cluster-domain }}, {{ cluster-name }}, {{ hostname }}, {{ id }}, {{ ip-labels }}, {{ ip-type }}, {{ pool }}, {{ role }}"
  type        = string
  default     = null
}

variable "cluster_rdns_ipv4" {
  description = "Defines the IPv4-specific reverse DNS FQDN for the cluster, crucial for network operations and service discovery. Supports dynamic placeholders: {{ cluster-domain }}, {{ cluster-name }}, {{ hostname }}, {{ id }}, {{ ip-labels }}, {{ ip-type }}, {{ pool }}, {{ role }}"
  type        = string
  default     = null
}

variable "cluster_rdns_ipv6" {
  description = "Defines the IPv6-specific reverse DNS FQDN for the cluster, crucial for network operations and service discovery. Supports dynamic placeholders: {{ cluster-domain }}, {{ cluster-name }}, {{ hostname }}, {{ id }}, {{ ip-labels }}, {{ ip-type }}, {{ pool }}, {{ role }}"
  type        = string
  default     = null
}

variable "cluster_talosconfig_path" {
  description = "If not null, the talosconfig will be written to a file speficified"
  type        = string
  default     = null
}

variable "control_plane_config_patches" {
  description = "List of configuration patches applied to the Control Plane nodes"
  type        = any
  default     = []
}

variable "control_plane_private_vip_ipv4_enabled" {
  description = "If true, an alias IP will be created and assigned to the Control Plane nodes"
  type        = bool
  default     = true
}

variable "control_plane_public_vip_ipv4_enabled" {
  description = "If true, a floating IP will be created and assigned to the Control Plane nodes"
  type        = bool
  default     = false
}

variable "control_plane_public_vip_ipv4_id" {
  description = "Specifies the Floating IP ID for the Control Plane nodes. A new floating IP will be created if this is set to null"
  type        = number
  default     = null
}

variable "firewall_api_source" {
  description = "Source networks that have access to Kube and Talos API. If set, this overrides the firewall_use_current_ipv4 and firewall_use_current_ipv6 settings"
  type        = list(string)
  default     = null
}

variable "firewall_extra_rules" {
  description = "Additional firewall rules to apply to the cluster"
  type = list(object({
    description     = string
    direction       = string
    source_ips      = optional(list(string), [])
    destination_ips = optional(list(string), [])
    protocol        = string
    port            = optional(string)
  }))
  default = []
}

variable "firewall_id" {
  description = "ID of an existing Hetzner Cloud Firewall to use instead of creating a new one. When set, firewall management is delegated to an external resource and this module will only attach the firewall to servers"
  type        = number
  default     = null
}

variable "firewall_kube_api_source" {
  description = "Source networks that have access to Kube API. If set, this overrides the firewall_use_current_ipv4 and firewall_use_current_ipv6 settings"
  type        = list(string)
  default     = null
}

variable "firewall_talos_api_source" {
  description = "Source networks that have access to Talos API. If set, this overrides the firewall_use_current_ipv4 and firewall_use_current_ipv6 settings"
  type        = list(string)
  default     = null
}

variable "firewall_use_current_ipv4" {
  description = "Determines whether the current IPv4 address is used for Talos and Kube API firewall rules. If cluster_access is set to public, the default is true"
  type        = bool
  default     = null
}

variable "firewall_use_current_ipv6" {
  description = "Determines whether the current IPv6 /64 CIDR is used for Talos and Kube API firewall rules. If cluster_access is set to public, the default is true"
  type        = bool
  default     = null
}

variable "gateway_api_crds_enabled" {
  description = "Enables the Gateway API Custom Resource Definitions (CRDs) deployment"
  type        = bool
  default     = true
}

variable "gateway_api_crds_release_channel" {
  description = "Specifies the release channel for the Gateway API CRDs. Valid options are 'standard' or 'experimental'"
  type        = string
  default     = "standard"
}

variable "gateway_api_crds_version" {
  description = "Specifies the version of the Gateway API Custom Resource Definitions (CRDs) to deploy"
  type        = string
  default     = "v1.4.1"
}

variable "hcloud_ccm_enabled" {
  description = "Enables the Hetzner Cloud Controller Manager (CCM)"
  type        = bool
  default     = true
}

variable "hcloud_ccm_helm_chart" {
  description = "Name of the Helm chart used for deploying Hcloud CCM"
  type        = string
  default     = "hcloud-cloud-controller-manager"
}

variable "hcloud_ccm_helm_repository" {
  description = "URL of the Helm repository where the Hcloud CCM chart is located"
  type        = string
  default     = "https://charts.hetzner.cloud"
}

variable "hcloud_ccm_helm_values" {
  description = "Custom Helm values for the Hcloud CCM chart deployment. These values will merge with and will override the default values provided by the Hcloud CCM Helm chart"
  type        = any
  default     = {}
}

variable "hcloud_ccm_helm_version" {
  description = "Version of the Hcloud CCM Helm chart to deploy"
  type        = string
  default     = "1.29.2"
}

variable "hcloud_ccm_load_balancers_algorithm_type" {
  description = "Default Load Balancer algorithm for CCM-managed Load Balancers"
  type        = string
  default     = "least_connections"
}

variable "hcloud_ccm_load_balancers_disable_ipv6" {
  description = "Disables the use of IPv6 for Load Balancers by default"
  type        = bool
  default     = false
}

variable "hcloud_ccm_load_balancers_disable_private_ingress" {
  description = "Disables the use of the private network for ingress by default"
  type        = bool
  default     = true
}

variable "hcloud_ccm_load_balancers_disable_public_network" {
  description = "Disables the public interface of CCM-managed Load Balancers by default"
  type        = bool
  default     = false
}

variable "hcloud_ccm_load_balancers_enabled" {
  description = "Enable or disable Hetzner Cloud CCM Service Controller"
  type        = bool
  default     = true
}

variable "hcloud_ccm_load_balancers_health_check_interval" {
  description = "Default time interval in seconds in which health checks are performed"
  type        = number
  default     = 3
}

variable "hcloud_ccm_load_balancers_health_check_retries" {
  description = "Default amount of unsuccessful retries needed until a target is considered unhealthy"
  type        = number
  default     = 3
}

variable "hcloud_ccm_load_balancers_health_check_timeout" {
  description = "Default time in seconds after an attempt is considered a timeout"
  type        = number
  default     = 3
}

variable "hcloud_ccm_load_balancers_location" {
  description = "Default Hetzner location for CCM-managed Load Balancers"
  type        = string
  default     = null
}

variable "hcloud_ccm_load_balancers_type" {
  description = "Default Load Balancer type for CCM-managed Load Balancers"
  type        = string
  default     = "lb11"
}

variable "hcloud_ccm_load_balancers_use_private_ip" {
  description = "Configures Load Balancer server targets to use the private IP by default"
  type        = bool
  default     = true
}

variable "hcloud_ccm_load_balancers_uses_proxyprotocol" {
  description = "Enables the proxyprotocol for CCM-managed Load Balancers by default"
  type        = bool
  default     = false
}

variable "hcloud_ccm_network_routes_enabled" {
  description = "Enable or disable Hetzner Cloud CCM Route Controller"
  type        = bool
  default     = true
}

variable "hcloud_csi_enabled" {
  description = "Enables the Hetzner Container Storage Interface (CSI)"
  type        = bool
  default     = true
}

variable "hcloud_csi_encryption_passphrase" {
  description = "Passphrase for encrypting volumes created by the Hcloud CSI driver. If not provided, a random passphrase will be generated. The passphrase must be 8-512 characters long and contain only printable 7-bit ASCII characters"
  type        = string
  default     = null
}

variable "hcloud_csi_helm_chart" {
  description = "Name of the Helm chart used for deploying Hcloud CSI"
  type        = string
  default     = "hcloud-csi"
}

variable "hcloud_csi_helm_repository" {
  description = "URL of the Helm repository where the Hcloud CSI chart is located"
  type        = string
  default     = "https://charts.hetzner.cloud"
}

variable "hcloud_csi_helm_values" {
  description = "Custom Helm values for the Hcloud CSI chart deployment. These values will merge with and will override the default values provided by the Hcloud CSI Helm chart"
  type        = any
  default     = {}
}

variable "hcloud_csi_helm_version" {
  description = "Version of the Hcloud CSI Helm chart to deploy"
  type        = string
  default     = "2.18.3"
}

variable "hcloud_csi_storage_classes" {
  description = "User defined Hcloud CSI storage classes"
  type = list(object({
    name                = string
    encrypted           = bool
    reclaimPolicy       = optional(string, "Delete")
    defaultStorageClass = optional(bool, false)
    extraParameters     = optional(map(string), {})
  }))
  default = [
    {
      name                = "hcloud-volumes-encrypted"
      encrypted           = true
      defaultStorageClass = true
    },
    {
      name                = "hcloud-volumes"
      encrypted           = false
      defaultStorageClass = false
    }
  ]
}

variable "hcloud_csi_volume_extra_labels" {
  description = "Specifies default labels to apply to all newly created volumes. The value must be a map in the format key: value"
  type        = map(string)
  default     = {}
}

variable "hcloud_network" {
  description = "The Hetzner network resource of an existing network"
  type        = object({ id = number })
  default     = null
}

variable "hcloud_network_id" {
  description = "The Hetzner network ID of an existing network"
  type        = number
  default     = null
}

variable "ingress_load_balancer_algorithm" {
  description = "Specifies the algorithm used by the ingress load balancer. 'round_robin' distributes requests evenly across all servers, while 'least_connections' directs requests to the server with the fewest active connections"
  type        = string
  default     = "least_connections"
}

variable "ingress_load_balancer_health_check_interval" {
  description = "The interval (in seconds) between consecutive health checks. Must be between 3 and 60 seconds"
  type        = number
  default     = 3
}

variable "ingress_load_balancer_health_check_retries" {
  description = "The number of retries for a failed health check before marking the target as unhealthy. Must be between 0 and 5"
  type        = number
  default     = 3
}

variable "ingress_load_balancer_health_check_timeout" {
  description = "The timeout (in seconds) for each health check attempt. It cannot exceed the interval and must be a positive value"
  type        = number
  default     = 3
}

variable "ingress_load_balancer_pools" {
  description = "Defines configuration settings for Ingress Load Balancer pools within the cluster"
  type = list(object({
    name                    = string
    location                = string
    type                    = optional(string)
    labels                  = optional(map(string), {})
    count                   = optional(number, 1)
    target_label_selector   = optional(list(string), [])
    local_traffic           = optional(bool, false)
    load_balancer_algorithm = optional(string)
    public_network_enabled  = optional(bool)
    rdns                    = optional(string)
    rdns_ipv4               = optional(string)
    rdns_ipv6               = optional(string)
  }))
  default = []
}

variable "ingress_load_balancer_public_network_enabled" {
  description = "Enables or disables the public interface of the Load Balancer"
  type        = bool
  default     = true
}

variable "ingress_load_balancer_rdns" {
  description = "Specifies the general reverse DNS FQDN for the ingress load balancer, used for internal networking and service discovery. Supports dynamic substitution with placeholders: {{ cluster-domain }}, {{ cluster-name }}, {{ hostname }}, {{ id }}, {{ ip-labels }}, {{ ip-type }}, {{ pool }}, {{ role }}"
  type        = string
  default     = null
}

variable "ingress_load_balancer_rdns_ipv4" {
  description = "Defines the IPv4-specific reverse DNS FQDN for the ingress load balancer, crucial for network operations and service discovery. Supports dynamic placeholders: {{ cluster-domain }}, {{ cluster-name }}, {{ hostname }}, {{ id }}, {{ ip-labels }}, {{ ip-type }}, {{ pool }}, {{ role }}"
  type        = string
  default     = null
}

variable "ingress_load_balancer_rdns_ipv6" {
  description = "Defines the IPv6-specific reverse DNS FQDN for the ingress load balancer, crucial for network operations and service discovery. Supports dynamic placeholders: {{ cluster-domain }}, {{ cluster-name }}, {{ hostname }}, {{ id }}, {{ ip-labels }}, {{ ip-type }}, {{ pool }}, {{ role }}"
  type        = string
  default     = null
}

variable "ingress_load_balancer_type" {
  description = "Specifies the type of load balancer to be used for the ingress. Valid options are 'lb11', 'lb21', or 'lb31'"
  type        = string
  default     = "lb11"
}

variable "ingress_nginx_config" {
  description = "Global configuration passed to the ConfigMap consumed by the nginx controller"
  type        = any
  default     = {}
}

variable "ingress_nginx_enabled" {
  description = "Enables the deployment of the Ingress NGINX Controller. Requires cert_manager_enabled to be true"
  type        = bool
  default     = false
}

variable "ingress_nginx_helm_chart" {
  description = "Name of the Helm chart used for deploying Ingress NGINX Controller"
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_nginx_helm_repository" {
  description = "URL of the Helm repository where the Ingress NGINX Controller chart is located"
  type        = string
  default     = "https://kubernetes.github.io/ingress-nginx"
}

variable "ingress_nginx_helm_values" {
  description = "Custom Helm values for the Ingress NGINX Controller chart deployment. These values will merge with and will override the default values provided by the Ingress NGINX Controller Helm chart"
  type        = any
  default     = {}
}

variable "ingress_nginx_helm_version" {
  description = "Version of the Ingress NGINX Controller Helm chart to deploy"
  type        = string
  default     = "4.14.3"
}

variable "ingress_nginx_kind" {
  description = "Specifies the type of Kubernetes controller to use for ingress-nginx. Valid options are 'Deployment' or 'DaemonSet'"
  type        = string
  default     = "Deployment"
}

variable "ingress_nginx_replicas" {
  description = "Specifies the number of replicas for the NGINX Ingress controller. If not set, the default is 2 replicas for clusters with fewer than 3 Worker nodes, and 3 replicas for clusters with 4 or more Worker nodes"
  type        = number
  default     = null
}

variable "ingress_nginx_service_external_traffic_policy" {
  description = "Denotes if this Service desires to route external traffic to node-local or cluster-wide endpoints"
  type        = string
  default     = "Cluster"
}

variable "ingress_nginx_topology_aware_routing" {
  description = "Enables Topology Aware Routing for ingress-nginx with the service annotation service.kubernetes.io/topology-mode, routing traffic closer to its origin"
  type        = bool
  default     = false
}

variable "kube_api_admission_control" {
  description = "List of admission control settings for the Kube API. If set, this overrides the default admission control"
  type        = list(any)
  default     = []
}

variable "kube_api_extra_args" {
  description = "Specifies additional command-line arguments to be passed to the kube-apiserver. This allows for customization of the API server's behavior according to specific cluster requirements"
  type        = map(string)
  default     = {}
}

variable "kube_api_hostname" {
  description = "Specifies the hostname for external access to the Kubernetes API server. This must be a valid domain name, set to the API's public IP address"
  type        = string
  default     = null
}

variable "kube_api_load_balancer_enabled" {
  description = "Determines whether a load balancer is enabled for the Kubernetes API server. Enabling this setting provides high availability and distributed traffic management to the API server"
  type        = bool
  default     = false
}

variable "kube_api_load_balancer_public_network_enabled" {
  description = "Enables the public interface for the Kubernetes API load balancer. When enabled, the API is accessible publicly without a firewall"
  type        = bool
  default     = null
}

variable "kubernetes_kubelet_extra_args" {
  description = "Specifies additional command-line arguments to pass to the kubelet service. These arguments can customize or override default kubelet configurations, allowing for tailored cluster behavior"
  type        = map(string)
  default     = {}
}

variable "kubernetes_kubelet_extra_config" {
  description = "Specifies additional configuration settings for the kubelet service. These settings can customize or override default kubelet configurations, allowing for tailored cluster behavior"
  type        = any
  default     = {}
}

variable "kubernetes_version" {
  description = "Specifies the Kubernetes version to deploy"
  type        = string
  default     = "v1.33.7"
}

variable "longhorn_default_storage_class" {
  description = "Set Longhorn as the default storage class"
  type        = bool
  default     = false
}

variable "longhorn_enabled" {
  description = "Enable or disable Longhorn integration"
  type        = bool
  default     = false
}

variable "longhorn_helm_chart" {
  description = "Name of the Helm chart used for deploying Longhorn"
  type        = string
  default     = "longhorn"
}

variable "longhorn_helm_repository" {
  description = "URL of the Helm repository where the Longhorn chart is located"
  type        = string
  default     = "https://charts.longhorn.io"
}

variable "longhorn_helm_values" {
  description = "Custom Helm values for the Longhorn chart deployment. These values will merge with and will override the default values provided by the Longhorn Helm chart"
  type        = any
  default     = {}
}

variable "longhorn_helm_version" {
  description = "Version of the Longhorn Helm chart to deploy"
  type        = string
  default     = "1.10.2"
}

variable "metrics_server_enabled" {
  description = "Enables the the Kubernetes Metrics Server"
  type        = bool
  default     = true
}

variable "metrics_server_helm_chart" {
  description = "Name of the Helm chart used for deploying Metrics Server"
  type        = string
  default     = "metrics-server"
}

variable "metrics_server_helm_repository" {
  description = "URL of the Helm repository where the Longhorn chart is located"
  type        = string
  default     = "https://kubernetes-sigs.github.io/metrics-server"
}

variable "metrics_server_helm_values" {
  description = "Custom Helm values for the Metrics Server chart deployment. These values will merge with and will override the default values provided by the Metrics Server Helm chart"
  type        = any
  default     = {}
}

variable "metrics_server_helm_version" {
  description = "Version of the Metrics Server Helm chart to deploy"
  type        = string
  default     = "3.13.0"
}

variable "metrics_server_replicas" {
  description = "Specifies the number of replicas for the Metrics Server. Depending on the node pool size, a default of 1 or 2 is used if not explicitly set"
  type        = number
  default     = null
}

variable "metrics_server_schedule_on_control_plane" {
  description = "Determines whether to schedule the Metrics Server on control plane nodes. Defaults to 'true' if there are no configured worker nodes"
  type        = bool
  default     = null
}

variable "network_ipv4_cidr" {
  description = "Specifies the main IPv4 CIDR block for the network. This CIDR block is used to allocate IP addresses within the network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "network_native_routing_ipv4_cidr" {
  description = "Specifies the IPv4 CIDR block that the CNI assumes will be routed natively by the underlying network infrastructure without the need for SNAT"
  type        = string
  default     = null
}

variable "network_node_ipv4_cidr" {
  description = "Specifies the Node IPv4 CIDR used for allocating IP addresses to both Control Plane and Worker nodes within the cluster. If not explicitly provided, a default subnet is dynamically calculated from the specified network_ipv4_cidr"
  type        = string
  default     = null
}

variable "network_node_ipv4_subnet_mask_size" {
  description = "Specifies the IPv4 subnet mask size used for node pools within the cluster. This setting determines the network segmentation precision, with a smaller mask size allowing more IP addresses per subnet. If not explicitly provided, an optimal default size is dynamically calculated from the network_pod_ipv4_cidr"
  type        = number
  default     = null
}

variable "network_pod_ipv4_cidr" {
  description = "Defines the Pod IPv4 CIDR block allocated for use by pods within the cluster. This CIDR block is essential for internal pod communications. If a specific subnet is not provided, a default is dynamically calculated from the network_ipv4_cidr"
  type        = string
  default     = null
}

variable "network_service_ipv4_cidr" {
  description = "Specifies the Service IPv4 CIDR block used for allocating ClusterIPs to services within the cluster. If not provided, a default subnet is dynamically calculated from the specified network_ipv4_cidr"
  type        = string
  default     = null
}

variable "oidc_client_id" {
  description = "OIDC client ID that all tokens must be issued for. Required when oidc_enabled is true"
  type        = string
  default     = ""
}

variable "oidc_enabled" {
  description = "Enable OIDC authentication for Kubernetes API server"
  type        = bool
  default     = false
}

variable "oidc_group_mappings" {
  description = "List of OIDC groups mapped to Kubernetes roles and cluster roles"
  type = list(object({
    group         = string
    cluster_roles = optional(list(string), [])
    roles = optional(list(object({
      name      = string
      namespace = string
    })), [])
  }))
  default = []
}

variable "oidc_groups_claim" {
  description = "JWT claim to use as the user's groups"
  type        = string
  default     = "groups"
}

variable "oidc_groups_prefix" {
  description = "Prefix prepended to group claims to prevent clashes with existing names"
  type        = string
  default     = "oidc:"
}

variable "oidc_issuer_url" {
  description = "URL of the OIDC provider (e.g., https://your-oidc-provider.com). Required when oidc_enabled is true"
  type        = string
  default     = ""
}

variable "oidc_username_claim" {
  description = "JWT claim to use as the username"
  type        = string
  default     = "sub"
}

variable "packer_amd64_builder" {
  description = "Configuration for the server used when building the Talos AMD64 image with Packer"
  type = object({
    server_type     = optional(string, "cpx11")
    server_location = optional(string, "ash")
  })
  default = {}
}

variable "packer_arm64_builder" {
  description = "Configuration for the server used when building the Talos ARM64 image with Packer"
  type = object({
    server_type     = optional(string, "cax11")
    server_location = optional(string, "nbg1")
  })
  default = {}
}

variable "prometheus_operator_crds_enabled" {
  description = "Enables the Prometheus Operator Custom Resource Definitions (CRDs) deployment"
  type        = bool
  default     = true
}

variable "prometheus_operator_crds_version" {
  description = "Specifies the version of the Prometheus Operator Custom Resource Definitions (CRDs) to deploy"
  type        = string
  default     = "v0.88.1"
}

variable "rbac_cluster_roles" {
  description = "List of custom Kubernetes cluster roles to create"
  type = list(object({
    name = string
    rules = list(object({
      api_groups = list(string)
      resources  = list(string)
      verbs      = list(string)
    }))
  }))
  default = []
}

variable "rbac_roles" {
  description = "List of custom Kubernetes roles to create"
  type = list(object({
    name      = string
    namespace = string
    rules = list(object({
      api_groups = list(string)
      resources  = list(string)
      verbs      = list(string)
    }))
  }))
  default = []
}

variable "talos_backup_age_x25519_public_key" {
  description = "AGE X25519 Public Key for client side Talos Backup encryption"
  type        = string
  default     = null
}

variable "talos_backup_enable_compression" {
  description = "Enable ETCD snapshot compression with zstd algorithm"
  type        = bool
  default     = false
}

variable "talos_backup_s3_access_key" {
  description = "S3 Access Key for Talos Backup"
  type        = string
  default     = ""
}

variable "talos_backup_s3_bucket" {
  description = "S3 bucket name for Talos Backup"
  type        = string
  default     = null
}

variable "talos_backup_s3_enabled" {
  description = "Enable Talos etcd S3 backup cronjob"
  type        = bool
  default     = true
}

variable "talos_backup_s3_endpoint" {
  description = "S3 endpoint for Talos Backup"
  type        = string
  default     = null
}

variable "talos_backup_s3_hcloud_url" {
  description = "Hetzner Cloud S3 endpoint for Talos Backup"
  type        = string
  default     = null
}

variable "talos_backup_s3_path_style" {
  description = "Use path style S3 for Talos Backup. Set this to false if you have another s3 like endpoint such as minio"
  type        = bool
  default     = false
}

variable "talos_backup_s3_prefix" {
  description = "S3 prefix for Talos Backup"
  type        = string
  default     = null
}

variable "talos_backup_s3_region" {
  description = "S3 region for Talos Backup"
  type        = string
  default     = null
}

variable "talos_backup_s3_secret_key" {
  description = "S3 Secret Access Key for Talos Backup"
  type        = string
  default     = ""
}

variable "talos_backup_schedule" {
  description = "The schedule for Talos Backup"
  type        = string
  default     = "0 * * * *"
}

variable "talos_backup_version" {
  description = "Specifies the version of Talos Backup to be used in generated machine configurations"
  type        = string
  default     = "v0.1.0-beta.3-3-g38dad7c"
}

variable "talos_ccm_enabled" {
  description = "Enables the Talos Cloud Controller Manager (CCM) deployment"
  type        = bool
  default     = true
}

variable "talos_ccm_version" {
  description = "Specifies the version of the Talos Cloud Controller Manager (CCM) to use. This version controls cloud-specific integration features in the Talos operating system"
  type        = string
  default     = "v1.11.0"
}

variable "talos_coredns_enabled" {
  description = "Determines whether CoreDNS is enabled in the Talos cluster. When enabled, CoreDNS serves as the primary DNS service provider in Kubernetes"
  type        = bool
  default     = true
}

variable "talos_discovery_kubernetes_enabled" {
  description = "Enable or disable Kubernetes-based Talos discovery service. Deprecated as of Kubernetes v1.32, where the AuthorizeNodeWithSelectors feature gate is enabled by default"
  type        = bool
  default     = false
}

variable "talos_discovery_service_enabled" {
  description = "Enable or disable Sidero Labs public Talos discovery service"
  type        = bool
  default     = true
}

variable "talos_ephemeral_partition_encryption_enabled" {
  description = "Enables or disables encryption for the ephemeral (/var) partition. Attention: Changing this value for an existing cluster requires manual actions as per Talos documentation. Ignoring this may break your cluster"
  type        = bool
  default     = true
}

variable "talos_extra_host_entries" {
  description = "Specifies additional host entries to be added on each node. Each entry must include an IP address and a list of aliases associated with that IP"
  type = list(object({
    ip      = string
    aliases = list(string)
  }))
  default = []
}

variable "talos_extra_inline_manifests" {
  description = "List of additional inline Kubernetes manifests to append to the Talos machine configuration during bootstrap"
  type = list(object({
    name     = string
    contents = string
  }))
  default = null
}

variable "talos_extra_kernel_args" {
  description = "Defines a list of extra kernel commandline parameters"
  type        = list(string)
  default     = []
}

variable "talos_extra_remote_manifests" {
  description = "List of remote URLs pointing to Kubernetes manifests to be appended to the Talos machine configuration during bootstrap"
  type        = list(string)
  default     = null
}

variable "talos_extra_routes" {
  description = "Specifies CIDR blocks to be added as extra routes for the internal network interface, using the Hetzner router (first usable IP in the network) as the gateway"
  type        = list(string)
  default     = []
}

variable "talos_image_extensions" {
  description = "Specifies Talos image extensions for additional functionality on top of the default Talos Linux capabilities. See: https://github.com/siderolabs/extensions"
  type        = list(string)
  default     = []
}

variable "talos_ipv6_enabled" {
  description = "Determines whether IPv6 is enabled for the Talos operating system. Enabling this setting configures the Talos OS to support IPv6 networking capabilities"
  type        = bool
  default     = true
}

variable "talos_kernel_modules" {
  description = "Defines a list of kernel modules to be loaded during system boot, along with optional parameters for each module. This allows for customized kernel behavior in the Talos environment"
  type = list(object({
    name       = string
    parameters = optional(list(string))
  }))
  default = null
}

variable "talos_kubelet_extra_mounts" {
  description = "Defines extra kubelet mounts for Talos with configurable 'source', 'destination' (defaults to 'source' if unset), 'type' (defaults to 'bind'), and 'options' (defaults to ['bind', 'rshared', 'rw'])"
  type = list(object({
    source      = string
    destination = optional(string)
    type        = optional(string, "bind")
    options     = optional(list(string), ["bind", "rshared", "rw"])
  }))
  default = []
}

variable "talos_logging_destinations" {
  description = "List of objects defining remote destinations for Talos service logs"
  type = list(object({
    endpoint  = string
    format    = optional(string, "json_lines")
    extraTags = optional(map(string), {})
  }))
  default = []
}

variable "talos_machine_configuration_apply_mode" {
  description = "Determines how changes to Talos machine configurations are applied. 'auto' (default) applies changes immediately and reboots if necessary. 'reboot' applies changes and then reboots the node. 'no_reboot' applies changes immediately without a reboot, failing if a reboot is required. 'staged' stages changes to apply on the next reboot without initiating a reboot"
  type        = string
  default     = "auto"
}

variable "talos_nameservers" {
  description = "Specifies a list of IPv4 and IPv6 nameserver addresses used for DNS resolution by nodes and CoreDNS within the cluster"
  type        = list(string)
  default     = ["185.12.64.1", "185.12.64.2", "2a01:4ff:ff00::add:1", "2a01:4ff:ff00::add:2"]
}

variable "talos_public_ipv4_enabled" {
  description = "Determines whether public IPv4 addresses are enabled for nodes the cluster. If true, each node is assigned a public IPv4 address"
  type        = bool
  default     = true
}

variable "talos_public_ipv6_enabled" {
  description = "Determines whether public IPv6 addresses are enabled for nodes in the cluster. If true, each node is assigned a public IPv4 address"
  type        = bool
  default     = true
}

variable "talos_registries" {
  description = "Specifies a list of registry mirrors to be used for container image retrieval. This configuration helps in specifying alternate sources or local mirrors for image registries, enhancing reliability and speed of image downloads"
  type        = any
  default     = null
}

variable "talos_schematic_id" {
  description = "Specifies the Talos schematic ID used for selecting the specific Image and Installer versions in deployments. This has precedence over talos_image_extensions"
  type        = string
  default     = null
}

variable "talos_state_partition_encryption_enabled" {
  description = "Enables or disables encryption for the state (/system/state) partition. Attention: Changing this value for an existing cluster requires manual actions as per Talos documentation. Ignoring this may break your cluster"
  type        = bool
  default     = true
}

variable "talos_sysctls_extra_args" {
  description = "Specifies a map of sysctl key-value pairs for configuring additional kernel parameters. These settings allow for detailed customization of the operating system's behavior at runtime"
  type        = map(string)
  default     = {}
}

variable "talos_time_servers" {
  description = "Specifies a list of time server addresses used for network time synchronization across the cluster. These servers ensure that all cluster nodes maintain accurate and synchronized time"
  type        = list(string)
  default     = ["ntp1.hetzner.de", "ntp2.hetzner.com", "ntp3.hetzner.net"]
}

variable "talos_upgrade_debug" {
  description = "Enable debug operation from kernel logs during Talos upgrades. When true, --wait is set to true by talosctl"
  type        = bool
  default     = false
}

variable "talos_upgrade_force" {
  description = "Force the Talos upgrade by skipping etcd health and member checks"
  type        = bool
  default     = false
}

variable "talos_upgrade_insecure" {
  description = "Upgrade using the insecure (no auth) maintenance service"
  type        = bool
  default     = false
}

variable "talos_upgrade_reboot_mode" {
  description = "Select the reboot mode during upgrade. Mode 'powercycle' bypasses kexec. Valid values: 'default' or 'powercycle'"
  type        = string
  default     = null
}

variable "talos_upgrade_stage" {
  description = "Stage the Talos upgrade to perform it after a reboot"
  type        = bool
  default     = false
}

variable "talos_version" {
  description = "Specifies the version of Talos to be used in generated machine configurations"
  type        = string
  default     = "v1.11.6"
}

variable "talosctl_retries" {
  description = "Specifies how many times talosctl operations should retry before failing. This setting helps improve resilience against transient network issues or temporary API unavailability"
  type        = number
  default     = 10
}

variable "talosctl_version_check_enabled" {
  description = "Controls whether a preflight check verifies the local talosctl client version before provisioning"
  type        = bool
  default     = true
}

variable "worker_config_patches" {
  description = "List of configuration patches applied to the Worker nodes"
  type        = any
  default     = []
}

variable "worker_nodepools" {
  description = "Defines configuration settings for Worker node pools within the cluster"
  type = list(object({
    name            = string
    location        = string
    type            = string
    backups         = optional(bool, false)
    keep_disk       = optional(bool, false)
    labels          = optional(map(string), {})
    annotations     = optional(map(string), {})
    taints          = optional(list(string), [])
    count           = optional(number, 1)
    rdns            = optional(string)
    rdns_ipv4       = optional(string)
    rdns_ipv6       = optional(string)
    placement_group = optional(bool, true)
  }))
  default = []
}