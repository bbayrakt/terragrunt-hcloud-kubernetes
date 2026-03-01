output "release_names" {
  description = "Helm release names managed by this module"
  value = [
    for release in concat(
      values(helm_release.wave_1),
      values(helm_release.wave_2),
      values(helm_release.wave_3),
    ) : release.name
  ]
}

output "release_namespaces" {
  description = "Namespace per Helm release"
  value = merge(
    { for key, release in helm_release.wave_1 : key => release.namespace },
    { for key, release in helm_release.wave_2 : key => release.namespace },
    { for key, release in helm_release.wave_3 : key => release.namespace },
  )
}
