# common Helm Chart

## Upgrading to 1.3.0

Versions before 1.3.0 created `ExternalSecret` objects as Helm hooks, so Helm did
not track them as ordinary release resources. Adopt the live objects before the
first 1.3.0 upgrade. **Do not delete live ExternalSecrets to work around Helm's
ownership check**; deletion can interrupt secret reconciliation.

1. Keep all ExternalSecret names unchanged for the adoption upgrade and collect
   the exact live names produced by the existing release values.
2. For every ExternalSecret created by the release, apply Helm's standard
   ownership metadata and remove the legacy hook annotations:

   ```bash
   release=my-release
   namespace=my-namespace
   external_secret_names=(my-release-common-first my-release-common-second)

   for name in "${external_secret_names[@]}"; do
     kubectl --namespace "$namespace" label externalsecret "$name" \
       app.kubernetes.io/managed-by=Helm \
       --overwrite
     kubectl --namespace "$namespace" annotate externalsecret "$name" \
       meta.helm.sh/release-name="$release" \
       meta.helm.sh/release-namespace="$namespace" \
       helm.sh/hook- \
       helm.sh/hook-weight- \
       helm.sh/hook-delete-policy- \
       --overwrite
   done
   ```

3. Upgrade to 1.3.0 with those names still unchanged:

   ```bash
   chart_ref=path-or-repository/common
   values_file=path/to/release-values.yaml

   helm upgrade "$release" "$chart_ref" \
     --namespace "$namespace" \
     --version 1.3.0 \
     --values "$values_file"
   ```

4. After that upgrade succeeds, Helm tracks the ExternalSecrets. Retained names
   update in place without disrupting their generated Secrets. A later upgrade
   that renames or removes an entry prunes the old ExternalSecret. With the
   default `creationPolicy: Owner`, Kubernetes then removes its generated Secret
   through owner garbage collection. `deletionPolicy: Retain` applies when the
   provider value disappears; it does not preserve a Secret when its
   ExternalSecret is deleted.

## Testing

```bash
helm lint charts/common --values charts/common/test-values.yaml
charts/common/tests/external-secret-lifecycle.sh
```

The lifecycle script is a Helm render-contract test. It does not perform an
upgrade against a Kubernetes cluster.
